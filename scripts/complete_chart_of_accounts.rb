#!/usr/bin/env ruby
# Completes the chart_of_accounts CSV from onoma/accounts.
#
# Matching is SEMANTIC, not code-based: the CSV and onoma share the French PCG
# numbering but assign different reference_names to the same code, so fr_pcga/fr_pcg82
# are NOT reliable join keys (~28% disagreement measured).
#
# To fill an empty `name`, in priority order:
#   1. the row's `previous_name`, when it is itself a valid onoma account name
#      (97.5% of previous_name values are — it is the curated onoma reference), then
#   2. a unique match of the row's French `label_fr` to one onoma account's French label.
# An onoma account is also resolved for already-named rows (exact name) to enrich codes.
# From the resolved onoma account we fill empty `label_fr` and the new fr_pcg2019 /
# fr_pcg2023 columns. Non-destructive: never overwrites a non-empty value.
#
# The container mounts ./data read-only, so this script READS the CSV in place and
# writes the completed CSV to STDOUT; the report goes to STDERR. Run it via stdin and
# capture stdout on the host:
#
#   docker compose -f docker-compose-dev.yml exec -T lexicon_runner \
#     bundle exec ruby - < scripts/complete_chart_of_accounts.rb \
#     > "data/chart_of_accounts/chart_of_accounts - chart_of_accounts.csv"
#
# CSV_PATH can be overridden via the env var of the same name.

require 'onoma'
require 'csv'
require 'i18n'

CSV_PATH = ENV.fetch('CSV_PATH', '/lexicon/data/chart_of_accounts/chart_of_accounts - chart_of_accounts.csv')

def blank_val?(v)
  v.nil? || v.to_s.strip.empty? || v.to_s.strip.upcase == 'NONE'
end

def norm_label(v)
  return nil if blank_val?(v)
  I18n.transliterate(v.to_s.downcase.strip, locale: :eng).gsub(/[^a-z0-9]+/, ' ').strip
end

# ---- Load onoma accounts -------------------------------------------------
I18n.available_locales = %i[fra eng]
Onoma.load_locales
I18n.reload!
Onoma.load!
accounts = Onoma['accounts']

by_name  = {}
by_label = Hash.new { |h, k| h[k] = [] }

accounts.list.each do |item|
  by_name[item.name] = item
  lbl = norm_label(item.l(locale: :fra))
  by_label[lbl] << item if lbl
end

def uniq_label(bucket, key)
  return nil if blank_val?(key)
  items = bucket[key.to_s.strip]
  items && items.size == 1 ? items.first : nil
end

def code(item, prop)
  v = item.attributes[prop]
  blank_val?(v) ? nil : v.to_s
end

# ---- Walk the CSV --------------------------------------------------------
rows = CSV.read(CSV_PATH, headers: true)
headers = rows.headers.dup
%w[fr_pcg2019 fr_pcg2023].each { |h| headers << h unless headers.include?(h) }

stats = Hash.new(0)
unmatched = []

output = CSV.generate do |csv|
  csv << headers
  rows.each do |row|
    h = headers.each_with_object({}) { |k, acc| acc[k] = row[k] }

    item = nil
    if blank_val?(h['name'])
      prev = h['previous_name'].to_s.strip
      if !blank_val?(prev) && by_name.key?(prev)
        item, via = by_name[prev], 'previous_name'
      else
        m = uniq_label(by_label, norm_label(h['label_fr']))
        item, via = m, 'label' if m
      end
      if item
        h['name'] = item.name
        stats[:filled_name] += 1
        stats["matched_#{via}"] += 1
      end
    else
      item = by_name[h['name'].to_s.strip]   # already named: resolve for enrichment only
      stats[:matched_existing] += 1 if item
    end

    if item
      if blank_val?(h['label_fr'])
        h['label_fr'] = item.l(locale: :fra)
        stats[:filled_label] += 1
      end
      if blank_val?(h['fr_pcg2019']) && (c = code(item, 'fr_pcg2019'))
        h['fr_pcg2019'] = c
        stats[:filled_pcg2019] += 1
      end
      if blank_val?(h['fr_pcg2023']) && (c = code(item, 'fr_pcg2023'))
        h['fr_pcg2023'] = c
        stats[:filled_pcg2023] += 1
      end
    else
      stats[:unmatched] += 1
      unmatched << h['N°'] if blank_val?(h['name'])
    end

    csv << headers.map { |k| h[k] }
  end
end

# ---- Report (STDERR) -----------------------------------------------------
warn "Total rows:                     #{rows.size}"
warn "Filled name via previous_name:  #{stats['matched_previous_name']}"
warn "Filled name via unique label:   #{stats['matched_label']}"
warn "Already-named (onoma-resolved):  #{stats[:matched_existing]}"
warn "-> filled name total:           #{stats[:filled_name]}"
warn "-> filled label_fr:             #{stats[:filled_label]}"
warn "-> filled fr_pcg2019:           #{stats[:filled_pcg2019]}"
warn "-> filled fr_pcg2023:           #{stats[:filled_pcg2023]}"
warn "Still name-less rows (N°): #{unmatched.size}"
warn "   #{unmatched.first(40).join(', ')}#{unmatched.size > 40 ? ' ...' : ''}"

# ---- Completed CSV (STDOUT) ---------------------------------------------
print output

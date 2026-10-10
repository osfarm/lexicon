# frozen_string_literal: true

require 'cgi'

module Lexicon
  module Contribution
    module Web
      # The pages of the local interface, in French like the review they show. They load nothing from
      # elsewhere: the interface works without a network.
      class Pages
        GUIDE = 'https://lexicon.osfarm.org/contribute'
        # Lines of a table shown under its name
        PREVIEWED = 8
        # Values of a column shown beside its type
        EXAMPLES = 3
        # Characters of a value shown as an example
        EXAMPLE_SIZE = 40

        TYPES = { 'text' => 'texte', 'integer' => 'nombre entier', 'number' => 'nombre', 'date' => 'date', 'datetime' => 'date et heure',
                  'boolean' => 'oui / non',
                  'point' => 'point géographique' }.freeze
        PIVOTS = {
          'commune' => 'une commune (code INSEE)', 'department' => 'un département', 'siren' => 'une entreprise (SIREN)',
          'siret' => 'un établissement (SIRET)',
          'cadastral_parcel' => 'une parcelle cadastrale', 'cap_crop_code' => 'une culture de la PAC', 'taxon' => 'un taxon',
          'production' => 'une production', 'weather_station' => 'une station météo', 'amm' => 'un produit phytosanitaire (AMM)',
          'variant' => 'un article du référentiel', 'commune_postal_code' => 'le code postal d’une commune (avec son nom)',
          'commune_name' => 'le nom d’une commune (avec son code postal)'
        }.freeze
        LICENCES = ['Licence Ouverte 2.0', 'CC0 1.0', 'CC-BY 4.0', 'CC-BY-SA 4.0', 'ODbL 1.0'].freeze
        # Label, name of the field, where it is in the sheet, what to write when it is empty
        FIELDS = [
          ['Ce que contient le jeu', 'description', ['description'], 'Une phrase, affichée au catalogue'],
          ['Qui le propose', 'author', ['author'], 'Prénom Nom, organisme'],
          ['Nom de la source', 'source_name', %w[source name], "Nom du jeu de données d'origine"],
          ['Adresse de la source', 'source_url', %w[source url], 'https://…'],
          ['Qui publie la source', 'source_provider', %w[source provider], 'Organisme'],
          ['Licence de la source', 'source_licence', %w[source licence], 'Licence Ouverte 2.0'],
          ['Adresse du texte de la licence', 'source_licence_url', %w[source licence_url], 'https://…'],
          ['Date des données', 'source_date', %w[source date], 'AAAA-MM-JJ']
        ].freeze

        STYLE = <<~CSS
          :root { --ink: #1d2b2e; --soft: #5b6b6e; --rule: #d8e0e0; --surface: #f3f6f6; --ok: #1f7a4d; --nok: #b3261e;
                  --warn: #8a5a00; --main: #0b5d6b; }
          * { box-sizing: border-box; }
          body { margin: 0; font: 16px/1.5 system-ui, sans-serif; color: var(--ink); background: #fff; }
          header { background: var(--ink); color: #fff; padding: 0.8rem 1.25rem; }
          header a { color: #fff; text-decoration: none; font-weight: 700; }
          header span { color: #b9d3d6; margin-left: 0.75rem; }
          header a.leave { float: right; font-weight: 400; text-decoration: underline; }
          main { max-width: 64rem; margin: 0 auto; padding: 1.5rem 1.25rem 6rem; }
          h1 { font-size: 1.6rem; margin: 0 0 0.25rem; }
          h2 { font-size: 1.2rem; margin: 2.2rem 0 0.5rem; }
          h2 b { display: inline-block; width: 1.7rem; height: 1.7rem; line-height: 1.7rem; text-align: center; border-radius: 50%;
                 background: var(--main); color: #fff; font-size: 0.95rem; margin-right: 0.4rem; }
          h3 { font-size: 1rem; margin: 1.4rem 0 0.4rem; }
          p { margin: 0.4rem 0; }
          a { color: var(--main); }
          code, pre, textarea { font: 14px/1.45 ui-monospace, monospace; }
          code { background: var(--surface); padding: 0.05rem 0.3rem; border-radius: 4px; }
          .soft { color: var(--soft); }
          .verdict { border-radius: 8px; padding: 0.7rem 1rem; margin: 1rem 0; font-weight: 700; }
          .verdict.ok { background: #e3f3ea; color: var(--ok); }
          .verdict.nok { background: #fbe9e7; color: var(--nok); }
          .verdict p { font-weight: 400; color: var(--ink); }
          ul.findings { list-style: none; padding: 0; margin: 0.5rem 0; }
          ul.findings li { border-left: 4px solid var(--nok); background: var(--surface); padding: 0.5rem 0.8rem; margin-bottom: 0.4rem; }
          ul.findings.notes li { border-left-color: var(--warn); }
          .done { background: #e8f1fb; border-radius: 8px; padding: 0.7rem 1rem; margin: 0.8rem 0; }
          .done ul { margin: 0.3rem 0 0; padding-left: 1.2rem; }
          table { border-collapse: collapse; width: 100%; font-size: 14px; }
          th, td { text-align: left; padding: 0.35rem 0.6rem; border-bottom: 1px solid var(--rule); white-space: nowrap; }
          th { background: var(--surface); }
          td.line { color: var(--soft); text-align: right; width: 1%; }
          table.columns { table-layout: fixed; border: 1px solid var(--rule); }
          table.columns th, table.columns td { white-space: normal; vertical-align: top; }
          table.columns th:nth-child(2) { width: 11rem; }
          table.columns th:nth-child(3) { width: 19rem; }
          table.columns .key { width: 3.5rem; text-align: center; }
          table.columns thead th { position: sticky; top: 0; z-index: 1; }
          table.columns select { width: 100%; }
          td.column code { font-weight: 700; overflow-wrap: anywhere; }
          td.column small { display: block; color: var(--soft); overflow-wrap: anywhere; margin-top: 0.15rem; }
          @media (max-width: 46rem) {
            table.columns th:nth-child(2) { width: 8rem; }
            table.columns th:nth-child(3) { width: 10rem; }
          }
          .scroll { overflow-x: auto; border: 1px solid var(--rule); border-radius: 8px; }
          .drop { display: block; border: 2px dashed var(--main); border-radius: 12px; padding: 1.6rem 1rem; text-align: center;
                  background: var(--surface); cursor: pointer; margin: 0.6rem 0; }
          .drop.over { background: #dcecee; }
          .drop strong { display: block; font-size: 1.05rem; }
          .drop input { display: none; }
          .fields { display: grid; grid-template-columns: minmax(12rem, 16rem) 1fr; gap: 0.5rem 1rem; align-items: center; }
          .fields label { font-weight: 700; }
          textarea { width: 100%; min-height: 18rem; border: 1px solid var(--rule); border-radius: 8px; padding: 0.7rem; }
          input[type=text], input[type=url], input[type=date], select { font: inherit; padding: 0.35rem 0.6rem; border: 1px solid var(--rule);
                 border-radius: 8px; background: #fff; max-width: 100%; }
          .fields input { width: 100%; }
          .fields input[type=checkbox] { width: auto; }
          button { font: inherit; font-weight: 700; padding: 0.5rem 1.1rem; border: 0; border-radius: 8px; background: var(--main);
                   color: #fff; cursor: pointer; }
          button.quiet { background: #fff; color: var(--main); border: 1px solid var(--main); padding: 0.25rem 0.7rem; }
          details { margin-top: 1rem; }
          summary { cursor: pointer; color: var(--main); }
          .status { font-weight: 700; }
          .status.ok { color: var(--ok); }
          .status.nok { color: var(--nok); }
          .problem { color: var(--nok); font-weight: 700; }
          #busy { display: none; position: fixed; top: 0; left: 0; right: 0; z-index: 2; background: var(--main); color: #fff;
                  padding: 0.7rem 1.25rem; font-weight: 700; text-align: center; }
          #busy::before { content: ''; display: inline-block; width: 0.9rem; height: 0.9rem; margin-right: 0.6rem; vertical-align: -0.1rem;
                  border: 2px solid #fff; border-right-color: transparent; border-radius: 50%; animation: turn 0.8s linear infinite; }
          @keyframes turn { to { transform: rotate(360deg); } }
          button:disabled { opacity: 0.5; cursor: wait; }
          #etat { margin-left: 0.5rem; color: var(--ok); font-weight: 700; }
        CSS

        SCRIPT = <<~JS
          const page = document.body.dataset
          const at = location.pathname
          const part = (id) => document.getElementById(id)
          // What is typed and not yet saved, a save on its way, a table being read
          let timer = null
          let saving = false
          let again = false
          let busy = false

          const say = (message) => { part('etat').textContent = message }
          const wait = (message) => {
            busy = true
            part('busy').textContent = message
            part('busy').style.display = 'block'
          }
          const done = () => {
            busy = false
            part('busy').style.display = 'none'
          }
          // Puts the parts the server answers where they stand; what the contributor is typing in is left alone
          const show = (state, parts) => {
            page.fingerprint = state.fingerprint
            for (const id of parts) {
              const target = part(id)
              if (!target || target.contains(document.activeElement)) continue
              if (id === 'yaml') target.value = state.yaml
              else target.innerHTML = state[id]
            }
          }
          const ask = async (verb, path, body, headers = {}) => {
            const answer = await fetch(at + path, { method: verb, body, headers: { 'X-Lexicon-Token': page.token, ...headers } })
            if (!answer.ok) throw new Error(await answer.text())
            return answer.json()
          }
          const failed = (error) => {
            done()
            part('dropped').textContent = error.message
            part('dropped').className = 'problem'
          }

          // Every change of the form is saved and read again, without a button
          const save = async () => {
            const form = document.querySelector('form.sheet')
            if (!form) return
            if (saving) { again = true; return }
            saving = true
            say('Enregistrement…')
            try {
              const state = await ask('POST', '/fiche', new URLSearchParams(new FormData(form)))
              show(state, ['relecture', 'yaml'])
              say('Enregistré et relu à ' + new Date().toLocaleTimeString('fr-FR'))
            } catch (error) {
              say('Non enregistré : ' + error.message)
            }
            saving = false
            if (again) { again = false; await save() }
          }
          const flush = async () => {
            if (timer === null) return
            clearTimeout(timer)
            timer = null
            await save()
          }
          const later = (delay) => {
            clearTimeout(timer)
            say('…')
            timer = setTimeout(() => { timer = null; save() }, delay)
          }
          document.addEventListener('input', (event) => {
            if (event.target.closest('form.sheet') && event.target.matches('input[type=text], input[type=url]')) later(700)
          })
          document.addEventListener('change', (event) => { if (event.target.closest('form.sheet')) later(0) })
          document.addEventListener('submit', (event) => { if (event.target.closest('form.sheet, form.yaml')) event.preventDefault() })

          const everything = ['relecture', 'import', 'libres', 'colonnes', 'champs', 'yaml']
          const tables = ['relecture', 'import', 'libres', 'colonnes', 'yaml']
          const send = async (files) => {
            await flush()
            part('dropped').textContent = ''
            try {
              for (const file of files) {
                wait('Lecture de ' + file.name + ' en cours… quelques secondes pour un gros tableau.')
                show(await ask('PUT', '/fichiers/' + encodeURIComponent(file.name), file), tables)
              }
              done()
              part('tableaux').scrollIntoView({ behavior: 'smooth' })
            } catch (error) { failed(error) }
          }
          const act = async (path, fields, parts, message) => {
            await flush()
            if (message) wait(message)
            try {
              show(await ask('POST', path, new URLSearchParams(fields)), parts)
              done()
            } catch (error) { failed(error) }
          }
          document.addEventListener('click', (event) => {
            const button = event.target.closest('button[data-act]')
            if (!button) return
            event.preventDefault()
            if (button.dataset.act === 'detecter') {
              act('/detecter', { file: button.dataset.file }, tables, 'Lecture de ' + button.dataset.file + ' en cours… quelques secondes pour un gros tableau.')
            } else if (button.dataset.act === 'lu') {
              act('/lu', {}, ['import'])
            } else if (button.dataset.act === 'proposer' || button.dataset.act === 'retirer') {
              act('/' + button.dataset.act, {}, ['relecture'])
            } else if (button.dataset.act === 'yaml') {
              act('/fiche', { sheet: part('yaml').value }, everything.filter((id) => id !== 'yaml'), 'Enregistrement et relecture…')
            }
          })

          const zone = document.querySelector('.drop')
          if (zone) {
            zone.querySelector('input').addEventListener('change', async (event) => { await send(event.target.files); event.target.value = '' })
            zone.addEventListener('dragover', (event) => { event.preventDefault(); zone.classList.add('over') })
            zone.addEventListener('dragleave', () => zone.classList.remove('over'))
            zone.addEventListener('drop', (event) => { event.preventDefault(); zone.classList.remove('over'); send(event.dataTransfer.files) })
          }

          // A file changed on the disk, by a spreadsheet or an editor: the page follows
          setInterval(async () => {
            if (busy || saving || timer !== null) return
            const answer = await fetch(at + '/empreinte').catch(() => null)
            if (!answer || !answer.ok || (await answer.text()) === page.fingerprint) return
            if (busy || saving || timer !== null) return
            const state = await fetch(at + '/etat').then((reply) => reply.json()).catch(() => null)
            if (state && !busy && !saving && timer === null) show(state, everything)
          }, 2000)
        JS

        # @param [Array<Hash>] datasets name, errors, warnings, unreadable and proposed of each dataset
        # @param [Hash] context token, writable, root, prefix (path the pages are served under) and hosted
        #   (served online to the holder of a key, who proposes a dataset from the page)
        # @param [String, nil] problem why the dataset asked for was not created
        # @return [String]
        def index(datasets, context, problem: nil)
          layout('Proposer un jeu de données', <<~HTML, context: context)
            <h1>Proposer un jeu de données</h1>
            <p class="soft">Donnez un nom à votre jeu, déposez votre tableau (CSV, Excel ou LibreOffice) : ses colonnes sont
              reconnues, il reste à dire d'où il vient. <a href="#{GUIDE}">Le guide du contributeur</a> en dit plus.</p>
            <h2>Commencer un jeu</h2>
            #{context[:writable] ? creation(context, problem) : read_only}
            <h2>Vos jeux</h2>
            #{datasets.empty? ? '<p>Aucun jeu pour le moment.</p>' : list(datasets, context)}
          HTML
        end

        # @param [Hash] dataset name, raw, sheet, tables, loose, import, errors, warnings, unreadable, proposal, fingerprint
        # @param [Hash] context token, writable, root
        # @return [String]
        def dataset(dataset, context)
          name = e(dataset[:name])
          parts = parts(dataset, context)
          opening = context[:writable] ? '<form class="sheet">' : '<div>'

          place = context[:hosted] ? 'Votre jeu est gardé sur le serveur du Lexicon.' : "Dossier <code>data/contributions/#{name}/</code>."

          data = { fingerprint: dataset[:fingerprint], token: context[:token] }

          layout(dataset[:name], <<~HTML, data: data, script: true, context: context)
            <p><a href="#{home(context)}">← Tous les jeux</a></p>
            <h1>#{name}</h1>
            <p class="soft">#{place} Tout s'enregistre et se relit au fur et à mesure.
              <span id="etat"></span></p>
            <div id="relecture">#{parts[:relecture]}</div>
            <h2 id="tableaux"><b>1</b>Vos tableaux</h2>
            #{drop(context)}
            <div id="import">#{parts[:import]}</div>
            <div id="libres">#{parts[:libres]}</div>
            #{opening}
              <div id="colonnes">#{parts[:colonnes]}</div>
              <h2><b>2</b>D'où vient le jeu</h2>
              <div id="champs">#{parts[:champs]}</div>
            #{context[:writable] ? '</form>' : '</div>'}
            #{raw(dataset, context)}
          HTML
        end

        # @return [Hash] the parts of the page of a dataset that change, each under the id of the element that holds it
        def parts(dataset, context)
          tables = dataset[:tables].each_with_index.map { |table, index| columns(table, index, context) }.join

          { fingerprint: dataset[:fingerprint], relecture: verdict(dataset, context) + findings(dataset),
            import: imported(dataset[:import], context), libres: loose(dataset[:loose], context), colonnes: tables,
            champs: dataset[:sheet] ? fields(dataset[:sheet]) : '<p>La fiche ne se lit pas : la corriger ci-dessous.</p>',
            yaml: dataset[:raw] }
        end

        private

          def e(value)
            CGI.escapeHTML(value.to_s)
          end

          def layout(title, content, data: {}, script: false, context: {})
            attributes = data.map { |key, value| %( data-#{key}="#{e(value)}") }.join
            where = context[:hosted] ? 'contribuer, en ligne' : 'contribuer, sur ce poste'
            # Online, the key of the visitor is kept by the API, which also forgets it
            leave = context[:hosted] ? %(<a class="leave" href="#{context[:prefix]}/sortir">Fermer l’outil</a>) : ''

            <<~HTML
              <!doctype html>
              <html lang="fr">
              <head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
              <title>#{e(title)} · Lexicon</title><style>#{STYLE}</style></head>
              <body#{attributes}>
              <header><a href="#{home(context)}">Lexicon</a><span>#{where}</span>#{leave}</header>
              <div id="busy" role="status"></div>
              <main>#{content}</main>
              #{script ? "<script>#{SCRIPT}</script>" : ''}
              </body></html>
            HTML
          end

          # @return [String] address of the list of datasets
          def home(context)
            "#{context[:prefix]}/"
          end

          def counted(count, singular, plural)
            "#{count} #{count == 1 ? singular : plural}"
          end

          def token(context)
            %(<input type="hidden" name="token" value="#{e(context[:token])}">)
          end

          def list(datasets, context)
            rows = datasets.map do |dataset|
              link = %(<a href="#{context[:prefix]}/jeux/#{CGI.escape(dataset[:name])}">#{e(dataset[:name])}</a>)
              "<tr><td>#{link}</td><td>#{status(dataset)}</td></tr>"
            end

            %(<div class="scroll"><table><thead><tr><th>Jeu</th><th>Relecture</th></tr></thead><tbody>#{rows.join}</tbody></table></div>)
          end

          def status(dataset)
            if dataset[:unreadable]
              '<span class="status nok">fiche illisible</span>'
            elsif dataset[:errors].positive?
              %(<span class="status nok">#{counted(dataset[:errors], 'point', 'points')} à corriger</span>)
            elsif dataset[:proposed]
              %(<span class="status ok">proposé le #{e(dataset[:proposed])}</span>)
            else
              '<span class="status ok">peut être proposé</span>'
            end
          end

          def creation(context, problem)
            <<~HTML
              #{problem ? %(<p class="problem">#{e(problem)}</p>) : ''}
              <form method="post" action="#{context[:prefix]}/jeux">
                #{token(context)}
                <label>Nom du jeu, en minuscules, sans accent ni espace :
                  <input type="text" name="name" placeholder="releves_sol" required pattern="[a-z][a-z0-9_]*"></label>
                <button>Commencer</button>
              </form>
            HTML
          end

          def read_only
            '<p>Le dossier des contributions est en lecture seule ici : créer le dossier à la main, avec la fiche que donne ' \
              '<code>./lexicon new &lt;nom&gt; --tabular</code>.</p>'
          end

          def verdict(dataset, context = {})
            if dataset[:unreadable]
              %(<div class="verdict nok">La fiche ne se lit pas<p>#{e(dataset[:unreadable])}</p></div>)
            elsif dataset[:errors].any?
              %(<div class="verdict nok">#{counted(dataset[:errors].size, 'point', 'points')} à corriger avant de proposer le jeu</div>)
            elsif context[:hosted]
              proposal(dataset)
            else
              <<~HTML
                <div class="verdict ok">Le jeu peut être proposé (#{e(dataset[:proposal].join(', '))})
                  <p>Envoyer le dossier par une demande de fusion sur le dépôt, ou à un mainteneur d'OSFarm. Rien n'est mis
                    en service sans sa relecture.</p></div>
              HTML
            end
          end

          # Online, a dataset is proposed from its page: a maintainer then fetches it and builds it
          def proposal(dataset)
            if dataset[:proposed]
              <<~HTML
                <div class="verdict ok">Jeu proposé le #{e(dataset[:proposed])}
                  <p>Un mainteneur d'OSFarm va le relire. Ce que vous changez encore ici lui parviendra aussi. Rien n'est mis
                    en service sans sa relecture.</p>
                  <button type="button" class="quiet" data-act="retirer">Retirer la proposition</button></div>
              HTML
            else
              <<~HTML
                <div class="verdict ok">Le jeu peut être proposé (#{e(dataset[:proposal].join(', '))})
                  <p>Un mainteneur d'OSFarm le relira avant toute mise en service.</p>
                  <button type="button" data-act="proposer">Proposer ce jeu</button></div>
              HTML
            end
          end

          def findings(dataset)
            sections = [['À corriger', dataset[:errors], 'findings'], ['À savoir', dataset[:warnings], 'findings notes']]
            sections.map do |title, messages, style|
              next '' if messages.empty?

              %(<h3>#{title}</h3><ul class="#{style}">#{messages.map { |message| "<li>#{e(message)}</li>" }.join}</ul>)
            end.join
          end

          def drop(context)
            return '<p class="soft">Pour ajouter ou remplacer un tableau, l’enregistrer dans le dossier.</p>' unless context[:writable]

            <<~HTML
              <label class="drop"><strong>Déposer un tableau ici, ou cliquer pour le choisir</strong>
                CSV, Excel (.xlsx, .xls) ou LibreOffice (.ods). Ses colonnes et leurs types sont reconnus, ses valeurs remises en forme.
                <input type="file" accept="#{Import::EXTENSIONS.join(',')}" multiple></label>
              <p id="dropped" class="soft"></p>
            HTML
          end

          # What the last import did, said until the contributor has read it
          def imported(import, context)
            return '' if import.nil?
            return %(<p class="problem">#{e(import[:problem])}</p>) if import[:problem]

            notes = import[:notes].map { |note| "<li>#{e(note)}</li>" }.join
            read = context[:writable] ? ' <button type="button" class="quiet" data-act="lu">J’ai lu</button>' : ''
            title = "<strong>« #{e(import[:file])} » est lu.</strong> Vérifiez ce qui a été reconnu :"
            %(<div class="done">#{title}<ul>#{notes}</ul>#{read}</div>)
          end

          # Files dropped in the directory by hand, that the sheet does not describe yet
          def loose(files, context)
            return '' if files.empty? || !context[:writable]

            files.map do |file|
              button = %(<button type="button" class="quiet" data-act="detecter" data-file="#{e(file)}">Reconnaître ses colonnes</button>)
              %(<p><code>#{e(file)}</code> est dans le dossier mais n'est pas décrit. #{button}</p>)
            end.join
          end

          # The columns of a table: what was detected, for the contributor to check and correct
          def columns(table, index, context)
            preview = table[:preview]
            headers = preview ? preview[:head].first.to_a : []
            links = { '' => '—' }.merge(pivot_labels)
            rows = table[:columns].map do |column, type|
              checked = column == table[:key] ? ' checked' : ''
              title = ' title="Identifie chaque ligne"'
              key = %(<input type="radio" name="key|#{index}" value="#{e(column)}"#{checked}#{disabled(context)}#{title}>)

              <<~HTML
                <tr><td class="column"><code>#{e(column)}</code>#{examples(preview, headers.index(column))}</td>
                  <td>#{select("type|#{index}|#{column}", TYPES, type, context)}</td>
                  <td>#{select("pivot|#{index}|#{column}", links, table[:pivots][column].to_s, context)}</td>
                  <td class="key">#{key}</td></tr>
              HTML
            end
            sizes = [[preview && preview[:rows], 'ligne', 'lignes'], [rows.size, 'colonne', 'colonnes']]
            count = preview ? " : #{sizes.map { |size| counted(*size) }.join(', ')}" : ' : fichier absent ou illisible'

            <<~HTML
              <h3><code>#{e(table[:file])}</code>#{count}</h3>
              <table class="columns"><thead><tr><th>Colonne et exemples</th><th>Ce qu'elle contient</th><th>Ce qu'elle désigne</th>
                <th class="key">Clé</th></tr></thead><tbody>#{rows.join}</tbody></table>
              <p class="soft">« Clé » : la colonne qui identifie chaque ligne. « Ce qu'elle désigne » relie le jeu aux autres ; pour une
                commune sans code INSEE, désigner la colonne du code postal et celle du nom.</p>
              #{preview ? lines(preview) : ''}
            HTML
          end

          # A few values of a column, under its name: what tells best whether its type was guessed right
          def examples(preview, position)
            return '' if position.nil?

            values = preview[:head].drop(1).map { |line| line[position].to_s }.reject(&:empty?).uniq.first(EXAMPLES)
            shown = values.map { |value| value.size > EXAMPLE_SIZE ? "#{value[0, EXAMPLE_SIZE]}…" : value }

            values.empty? ? '<small>vide dans les premières lignes</small>' : "<small>#{e(shown.join(' · '))}</small>"
          end

          def pivot_labels
            keys = Packaging::Pivots::KEYS.keys + Sheet::PLACE_PARTS.keys

            keys.map { |key| [key, PIVOTS.fetch(key, key)] }.to_h
          end

          def disabled(context)
            context[:writable] ? '' : ' disabled'
          end

          def select(name, choices, chosen, context)
            choices = choices.merge(chosen => chosen) unless choices.key?(chosen)
            options = choices.map do |value, label|
              %(<option value="#{e(value)}"#{value == chosen ? ' selected' : ''}>#{e(label)}</option>)
            end

            %(<select name="#{e(name)}"#{disabled(context)}>#{options.join}</select>)
          end

          # Line numbers are the ones a spreadsheet shows, as in the review
          def lines(preview)
            headers, *lines = preview[:head]
            head = headers.to_a.map { |header| "<th>#{e(header)}</th>" }.join
            body = lines.each_with_index.map do |line, index|
              %(<tr><td class="line">#{index + 2}</td>#{line.map { |cell| "<td>#{e(cell)}</td>" }.join}</tr>)
            end

            <<~HTML
              <details><summary>Voir les #{counted(lines.size, 'première ligne', 'premières lignes')}</summary>
                <div class="scroll"><table><thead><tr><th></th>#{head}</tr></thead><tbody>#{body.join}</tbody></table></div></details>
            HTML
          end

          # A text of the skeleton is shown as a hint, not as what the contributor wrote
          def fields(sheet)
            inputs = FIELDS.map do |label, name, path, hint|
              value = sheet.data.dig(*path).to_s
              value = '' if value == Scaffold::PLACEHOLDERS[path.join('.')]
              kind = { 'source_date' => 'date', 'source_url' => 'url', 'source_licence_url' => 'url' }.fetch(name, 'text')
              list = name == 'source_licence' ? ' list="licences"' : ''

              input = %(<input type="#{kind}" id="#{name}" name="#{name}" value="#{e(value)}" placeholder="#{e(hint)}"#{list}>)
              %(<label for="#{name}">#{label}</label>#{input})
            end

            <<~HTML
              <div class="fields">#{inputs.join}
                <label for="members">Accès</label>
                <span><input type="checkbox" id="members" name="members" value="1"#{sheet.scope == 'members' ? ' checked' : ''}>
                  Réserver le jeu aux adhérents d'OSFarm (à cocher si la licence n'est pas ouverte)</span>
                <label for="personal_data">Données personnelles</label>
                <input type="text" id="personal_data" name="personal_data" value="#{e(sheet.personal_data)}"
                  placeholder="Seulement si une colonne en porte : dire pourquoi elle peut être publiée">
              </div>
              <datalist id="licences">#{LICENCES.map { |licence| %(<option value="#{e(licence)}">) }.join}</datalist>
            HTML
          end

          def raw(dataset, context)
            area = %(<textarea id="yaml" spellcheck="false"#{context[:writable] ? '' : ' readonly'}>#{e(dataset[:raw])}</textarea>)
            return "<details><summary>Fiche en YAML</summary>#{area}</details>" unless context[:writable]

            <<~HTML
              <details#{dataset[:sheet] ? '' : ' open'}><summary>Fiche en YAML (pour qui préfère l'écrire à la main)</summary>
                <form class="yaml">
                  #{area}
                  <p><button type="button" class="quiet" data-act="yaml">Enregistrer le YAML</button></p>
                </form></details>
            HTML
          end
      end
    end
  end
end

# frozen_string_literal: true

require 'concurrent'
require 'open3'
require 'shellwords'
require 'tempfile'
require 'yaml'

module Lexicon
  module Commands
    # Charge un package local `out/<version>/` dans une base PostgreSQL distante
    # accessible via SSH. Optimisé : streaming des .csv.gz (zéro temp file côté
    # serveur) + ControlMaster SSH (une seule TCP réutilisée pour tout le run).
    #
    # Utilisation : `./lexicon load <version> --target <profile>`
    # où <profile> est une entrée de `config/remote_targets.yml`.
    class LoadCommand < ContainerAwareCommand
      include Lexicon::Common::Mixin::SchemaNamer

      CONFIG_PATH = 'config/remote_targets.yml'

      desc 'remote VERSION', 'Stream a local package into a remote PostgreSQL via SSH'
      option :target,      type: :string,  required: true,
                           desc: "Nom du profil dans #{CONFIG_PATH}"
      option :only,        type: :array,   default: [],
                           desc: 'Liste de datasources à charger (vide = tous)'
      option :without,     type: :array,   default: [],
                           desc: 'Datasources à exclure'
      option :jobs,        type: :numeric, default: 4,
                           desc: 'Nombre de tables chargées en parallèle'
      option :keep_schema, type: :boolean, default: false,
                           desc: 'Ne pas DROP le schéma cible avant chargement'
      option :dry_run,     type: :boolean, default: false,
                           desc: 'Affiche le plan sans exécuter'

      def remote(version_name)
        target = load_target_config(options[:target])
        package = load_package(version_name)
        # `postgres.schema` dans le YAML sert d'override explicite, sinon on
        # dérive de la version (cohérent avec `production load` & `enable`).
        schema = target.dig('postgres', 'schema') || version_to_schema(package.version)

        file_sets = filter_file_sets(package.file_sets,
                                     only: split_csv_array(options[:only]),
                                     without: split_csv_array(options[:without]))

        if options[:dry_run]
          print_dry_run(target, package, schema, file_sets)
          return
        end

        with_ssh_control_socket(target) do |ssh_master|
          test_ssh_connectivity(ssh_master)
          test_remote_psql(ssh_master, target)

          unless options[:keep_schema]
            puts "Resetting schema #{schema.yellow} on #{target['name'].yellow}..."
            psql_pipe(ssh_master, target,
                      sql: %(DROP SCHEMA IF EXISTS "#{schema}" CASCADE;
                             CREATE SCHEMA "#{schema}";))
          end

          puts "Loading structures…"
          load_structures(ssh_master, target, package, schema)

          puts "Streaming data (#{options[:jobs]} parallel jobs)…"
          load_data(ssh_master, target, package, schema, file_sets, jobs: options[:jobs])
        end

        puts '[  OK ] '.green +
             "Package #{package.version.to_s.yellow} loaded into #{target['name'].yellow} " \
             "as schema #{schema.yellow}"
      end

      private

        # ── Configuration ─────────────────────────────────────────────────────

        # @return [Hash]
        def load_target_config(name)
          file = Pathname.new(CONFIG_PATH)
          unless file.exist?
            abort "[ NOK ] #{CONFIG_PATH} not found (cp #{CONFIG_PATH}.sample #{CONFIG_PATH})".red
          end

          all = YAML.safe_load(file.read) || {}
          target = all[name]
          if target.nil?
            abort "[ NOK ] Target '#{name}' not found in #{CONFIG_PATH}. " \
                  "Available: #{all.keys.join(', ')}".red
          end
          unless target.is_a?(Hash) && target['ssh'].is_a?(Hash) && target['postgres'].is_a?(Hash)
            abort "[ NOK ] Target '#{name}' is missing 'ssh:' or 'postgres:' section".red
          end
          target.merge('name' => name)
        end

        # @return [Lexicon::Common::Package::Package]
        def load_package(version_name)
          loader = get('production.package.loader')
          pkg = loader.load_package(version_name)
          abort "[ NOK ] Package #{version_name} not found in out/".red if pkg.nil?
          pkg
        end

        def filter_file_sets(file_sets, only:, without:)
          sets = file_sets.select { |fs| fs.respond_to?(:tables) && fs.tables.any? }
          sets = sets.select { |fs| only.include?(fs.name) }   if only.any?
          sets = sets.reject { |fs| without.include?(fs.name) }
          sets
        end

        # Thor avec `type: :array` split sur l'espace. On accepte aussi la
        # virgule pour permettre `--only=a,b,c` (plus naturel à la frappe).
        def split_csv_array(arr)
          Array(arr).flat_map { |s| s.to_s.split(',') }.map(&:strip).reject(&:empty?)
        end

        # ── SSH ControlMaster (réutilise une TCP pour tout le run) ────────────

        def with_ssh_control_socket(target)
          # Socket unique par process : évite les collisions entre runs.
          socket = Pathname.new(Dir.tmpdir).join("lexicon-load-#{Process.pid}.sock").to_s
          ssh_master = SshMaster.new(target: target['ssh'], socket: socket)

          begin
            ssh_master.start
            yield ssh_master
          ensure
            ssh_master.stop
          end
        end

        # ── Tests de connectivité avant le gros load ──────────────────────────

        def test_ssh_connectivity(ssh_master)
          stdout, stderr, status = ssh_master.exec('echo lexicon-ssh-ok')
          unless status.success? && stdout.include?('lexicon-ssh-ok')
            abort "[ NOK ] SSH connectivity test failed:\n#{stderr}".red
          end
        end

        def test_remote_psql(ssh_master, target)
          stdout, stderr, status = ssh_master.exec(psql_command(target) + ' -At -c "SELECT 1"')
          unless status.success? && stdout.strip == '1'
            abort "[ NOK ] Remote psql test failed:\nstdout=#{stdout.inspect}\nstderr=#{stderr}".red
          end
        end

        # ── Structures (DDL) ──────────────────────────────────────────────────

        def load_structures(ssh_master, target, package, schema)
          structure_files = package.files.select(&:structure?)
          structure_files.each do |sf|
            sql = package.dir.join(sf.path).read
            psql_pipe(ssh_master, target,
                      sql: %(SET search_path TO "#{schema}",public;\n) + sql)
          end
        end

        # ── Data (.csv.gz streamé via ssh stdin → psql \copy STDIN) ───────────

        def load_data(ssh_master, target, package, schema, file_sets, jobs:)
          tasks = file_sets.flat_map do |fs|
            fs.tables.flat_map do |table_name, files|
              files.map { |f| [fs.name, table_name, package.data_dir.join(f)] }
            end
          end

          remaining = ::Concurrent::Set.new(tasks.map { |t| t[2].basename.to_s })
          pool = ::Concurrent::FixedThreadPool.new(jobs)
          errors = ::Concurrent::Array.new

          tasks.each do |(ds_name, table_name, path)|
            pool.post do
              begin
                stream_csv_gz(ssh_master, target, schema: schema,
                                                  table: table_name, file: path)
                remaining.delete(path.basename.to_s)
                puts '[  OK ] '.green + path.basename.to_s.yellow +
                     " (#{ds_name}.#{table_name}), " \
                     "#{remaining_message(remaining)}"
              rescue StandardError => e
                errors << [ds_name, table_name, path, e]
              end
            end
          end

          pool.shutdown
          pool.wait_for_termination

          unless errors.empty?
            errors.each do |(ds, tbl, path, err)|
              puts '[ FAIL ] '.red + "#{ds}.#{tbl} (#{path.basename}): #{err.message}"
            end
            abort "[ NOK ] #{errors.size} table(s) failed to load".red
          end
        end

        def stream_csv_gz(ssh_master, target, schema:, table:, file:)
          # Local : zcat <file> | ssh user@host 'psql -c "\copy schema.table FROM STDIN WITH csv"'
          copy_sql = %(\\copy "#{schema}"."#{table}" FROM STDIN WITH csv)
          remote_cmd = "#{psql_command(target)} -c #{Shellwords.escape(copy_sql)}"
          ssh_cmd = ssh_master.command_for(remote_cmd)

          # Pipe zcat → ssh.
          Open3.pipeline_r("zcat #{Shellwords.escape(file.to_s)}", ssh_cmd) do |out, wait_threads|
            tail_output = out.read
            statuses = wait_threads.map(&:value)
            unless statuses.all?(&:success?)
              raise "exit codes #{statuses.map(&:exitstatus).inspect}: #{tail_output}"
            end
          end
        end

        # ── Remote psql command builder ───────────────────────────────────────

        def psql_command(target)
          pg = target['postgres']
          parts = []
          parts << "PGPASSWORD=#{Shellwords.escape(pg['password'])}" if pg['password']
          # `exec_wrapper` permet d'envelopper psql (ex. `docker exec -i <ct>`).
          # Indispensable quand psql vit dans un container sur le serveur cible.
          parts << pg['exec_wrapper'] if pg['exec_wrapper']
          parts << 'psql -X --quiet --pset=pager=off -v ON_ERROR_STOP=1'
          parts << "-h #{Shellwords.escape(pg['host'])}"       if pg['host']
          parts << "-p #{Shellwords.escape(pg['port'].to_s)}"  if pg['port']
          parts << "-U #{Shellwords.escape(pg['user'])}"       if pg['user']
          parts << "-d #{Shellwords.escape(pg['database'])}"   if pg['database']
          parts.join(' ')
        end

        # Exécute du SQL via ssh stdin → remote psql.
        def psql_pipe(ssh_master, target, sql:)
          remote_cmd = psql_command(target)
          ssh_cmd = ssh_master.command_for(remote_cmd)
          stdout, stderr, status = Open3.capture3(ssh_cmd, stdin_data: sql)
          unless status.success?
            raise "psql failed (#{status.exitstatus}):\n#{stderr}\n#{stdout}"
          end
        end

        # ── Helpers ───────────────────────────────────────────────────────────

        def remaining_message(remaining)
          n = remaining.size
          return 'all done'      if n.zero?
          return "#{n} remaining" if n > 5

          "remaining: #{remaining.to_a.sort.join(', ')}"
        end

        def print_dry_run(target, package, schema, file_sets)
          puts '── DRY RUN ──'.yellow
          puts "Target:  #{target['name']} (#{target.dig('ssh', 'user')}@#{target.dig('ssh', 'host')})"
          puts "Remote DB: #{target.dig('postgres', 'database')} on #{target.dig('postgres', 'host') || '<remote-local>'}:#{target.dig('postgres', 'port') || 5432}"
          puts "Package: #{package.version} (#{package.dir})"
          puts "Schema:  #{schema}"
          puts "Datasources: #{file_sets.size}"
          file_sets.each do |fs|
            tables_str = fs.tables.map { |name, files| "#{name} (#{files.size} file)" }.join(', ')
            puts "  - #{fs.name}: #{tables_str}"
          end
        end

      # SSH ControlMaster wrapper : ouvre une connexion TCP persistante au
      # démarrage et la réutilise pour chaque appel `exec` / `command_for`.
      # Sans ça, chaque `\copy` payerait un round-trip TLS de ~500 ms.
      class SshMaster
        # @param [Hash] target  partie 'ssh:' du profil
        # @param [String] socket  chemin de la socket de contrôle
        def initialize(target:, socket:)
          @target = target
          @socket = socket
        end

        # Démarre le master SSH en arrière-plan.
        def start
          cmd = "ssh #{base_opts} -M -N -f #{user_host}"
          system(cmd) || raise("Failed to start SSH master: #{cmd}")
        end

        # Termine proprement le master SSH (idempotent).
        def stop
          return unless File.exist?(@socket)

          system("ssh -S #{Shellwords.escape(@socket)} -O exit #{user_host} 2>/dev/null")
        rescue StandardError
          nil
        end

        # Construit la commande shell pour exécuter `remote_cmd` via la socket.
        # @param [String] remote_cmd
        # @return [String]
        def command_for(remote_cmd)
          "ssh -S #{Shellwords.escape(@socket)} #{user_host} #{Shellwords.escape(remote_cmd)}"
        end

        # Exécute une commande synchrone. Sépare stdout (= sortie du remote_cmd)
        # de stderr (= warnings ssh client + stderr du remote). Indispensable
        # quand on parse stdout : sans ça, des messages comme "Master refused
        # session request" du client SSH pollueraient la sortie utile.
        # @return [Array(String, String, Process::Status)]
        def exec(remote_cmd)
          Open3.capture3(command_for(remote_cmd))
        end

        private

          def base_opts
            opts = []
            opts << "-p #{Shellwords.escape(@target['port'].to_s)}" if @target['port']
            opts << "-i #{Shellwords.escape(@target['identity_file'])}" if @target['identity_file']
            Array(@target['options']).each { |o| opts << "-o #{Shellwords.escape(o)}" }
            opts << "-o ControlMaster=yes"
            opts << "-o ControlPath=#{Shellwords.escape(@socket)}"
            opts << "-o ControlPersist=60"
            opts.join(' ')
          end

          def user_host
            Shellwords.escape("#{@target['user']}@#{@target['host']}")
          end
      end
    end
  end
end

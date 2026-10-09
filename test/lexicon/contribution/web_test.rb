# frozen_string_literal: true

require 'test_helper'
require 'net/http'

module Lexicon
  module Contribution
    class WebTest < Minitest::Test
      SHEET = <<~YAML
        description: Relevés d'humidité des sols
        author: Camille Martin, GAEC des Prés
        source:
          name: Relevés de sondes
          url: https://example.org/sondes
          provider: GAEC des Prés
          licence: Licence Ouverte 2.0
          date: 2026-09-30
        tables:
          - file: releves.csv
            key: id
            columns:
              id: text
              value: number
      YAML

      def setup
        @root = Pathname.new(Dir.mktmpdir)
        @app = Web::App.new(root: @root, taken: %w[prices], token: 'secret')
      end

      def teardown
        FileUtils.chmod_R(0o755, @root)
        FileUtils.rm_rf(@root)
      end

      def test_list_says_where_each_dataset_stands
        dataset('releves_sol', "id,value\nr1,12.5\n")
        dataset('a_revoir', "id,value\nr1,douze\nr1,3\n")
        page = get('/').body

        assert_includes page, 'peut être proposé'
        assert_includes page, '2 points à corriger'
      end

      def test_page_of_a_dataset_shows_the_review_and_the_table
        dataset('releves_sol', "id,value\nr1,\"12,5\"\n")
        page = get('/jeux/releves_sol').body

        assert_includes page, '1 point à corriger avant de proposer le jeu'
        assert_includes page, CGI.escapeHTML("colonne « value » : 1 valeur n'est pas un nombre")
        assert_includes page, '<td>12,5</td>'
      end

      def test_what_a_file_holds_is_never_read_as_html
        dataset('releves_sol', "id,value\n<script>alert(1)</script>,1\n")

        refute_includes get('/jeux/releves_sol').body, '<script>alert(1)</script>'
      end

      def test_sheet_that_does_not_read_is_said_not_raised
        dataset('releves_sol', "id,value\nr1,1\n", sheet: "description: [oups\n")

        assert_includes get('/jeux/releves_sol').body, 'La fiche ne se lit pas'
        assert_includes get('/').body, 'fiche illisible'
      end

      def test_dataset_is_started_with_a_sheet_to_fill
        response = post('/jeux', 'name' => 'releves_sol', 'token' => 'secret')
        page = get('/jeux/releves_sol').body

        assert_equal 303, response.status
        assert_equal '/jeux/releves_sol', response.headers['Location']
        assert_equal 'Licence Ouverte 2.0', Sheet.load(@root.join('releves_sol')).source['licence']
        assert_includes page, 'La fiche ne renseigne pas « author ».'
        assert_includes page, 'Déposer un tableau ici'
      end

      def test_dropped_table_is_described_in_the_sheet
        post('/jeux', 'name' => 'releves_sol', 'token' => 'secret')
        sent = put('/jeux/releves_sol/fichiers/Relev%C3%A9s%202026.csv', "Code INSEE;Mesuré le;Valeur\n17387;01/09/2026;12,5\n28085;02/09/2026;8\n",
                   'x-lexicon-token' => 'secret')
        table = Sheet.load(@root.join('releves_sol')).tables.first
        page = get('/jeux/releves_sol').body

        assert_equal 200, sent.status
        assert_equal 'releves_2026.csv', table.file
        assert_equal({ 'code_insee' => 'text', 'mesure_le' => 'date', 'valeur' => 'number' }, table.columns)
        assert_equal 'code_insee', table.key
        assert_equal({ 'code_insee' => 'commune' }, table.pivots)
        assert_equal "code_insee,mesure_le,valeur\n17387,2026-09-01,12.5\n28085,2026-09-02,8\n", @root.join('releves_sol', 'releves_2026.csv').read
        assert_includes page, CGI.escapeHTML('La colonne « Code INSEE » s\'appelle maintenant « code_insee ».')
        assert_includes get('/jeux/releves_sol').body, 'appelle maintenant'
        assert_empty JSON.parse(post('/jeux/releves_sol/lu', 'token' => 'secret').body)['import']
        refute_includes get('/jeux/releves_sol').body, 'appelle maintenant'
      end

      def test_form_fills_the_sheet_and_corrects_what_was_detected
        post('/jeux', 'name' => 'releves_sol', 'token' => 'secret')
        put('/jeux/releves_sol/fichiers/releves.csv', "id,annee,valeur\nr1,2025,1\nr2,2026,2\n", 'x-lexicon-token' => 'secret')
        post('/jeux/releves_sol/fiche', 'token' => 'secret', 'description' => 'Relevés', 'author' => 'Camille Martin', 'source_name' => 'Sondes',
                                        'source_url' => 'https://example.org', 'source_provider' => 'GAEC', 'source_licence' => 'CC-BY 4.0',
                                        'source_date' => '2026-09-30', 'members' => '1', 'type|0|annee' => 'text', 'type|0|valeur' => 'faux',
                                        'key|0' => 'id', 'pivot|0|id' => 'siren', 'pivot|0|annee' => 'inconnu')
        sheet = Sheet.load(@root.join('releves_sol'))

        assert_equal 'Relevés', sheet.description
        assert_equal 'CC-BY 4.0', sheet.source['licence']
        assert_equal 'members', sheet.scope
        assert_equal({ 'id' => 'text', 'annee' => 'text', 'valeur' => 'integer' }, sheet.tables.first.columns)
        assert_equal({ 'id' => 'siren' }, sheet.tables.first.pivots)
        assert_includes get('/jeux/releves_sol').body, 'Le jeu peut être proposé'
      end

      def test_every_action_answers_the_parts_of_the_page_to_replace
        post('/jeux', 'name' => 'releves_sol', 'token' => 'secret')
        dropped = put('/jeux/releves_sol/fichiers/releves.csv', "id,valeur\nr1,1\nr2,2\n", 'x-lexicon-token' => 'secret')
        saved = post('/jeux/releves_sol/fiche', 'token' => 'secret', 'description' => 'Relevés', 'key|0' => 'id')
        followed = get('/jeux/releves_sol/etat')

        [dropped, saved, followed].each do |response|
          assert_equal 200, response.status
          assert_equal %w[champs colonnes fingerprint import libres relecture yaml], JSON.parse(response.body).keys.sort
        end
        assert_includes JSON.parse(dropped.body)['relecture'], 'La fiche ne renseigne pas « description ».'
        refute_includes JSON.parse(saved.body)['relecture'], 'La fiche ne renseigne pas « description ».'
        assert_equal get('/jeux/releves_sol/empreinte').body, JSON.parse(followed.body)['fingerprint']
        assert_includes JSON.parse(followed.body)['yaml'], 'description: Relevés'
      end

      def test_table_is_read_again_only_when_it_or_its_description_changes
        dataset('releves_sol', "id,value\nr1,douze\n")
        file = @root.join('releves_sol', 'releves.csv')
        memo = {}
        review = -> { Review.new(Sheet.load(@root.join('releves_sol')), memo: memo).findings.map(&:message) }
        first = review.call
        stamp = file.mtime
        file.write("id,value\nr1,12.50\n")
        File.utime(stamp, stamp, file)

        assert_equal first, review.call
        file.write("id,value\nr1,12\n")

        assert_empty review.call
      end

      def test_file_left_in_the_directory_can_be_described
        post('/jeux', 'name' => 'releves_sol', 'token' => 'secret')
        @root.join('releves_sol', 'mesures.csv').write("id;valeur\nm1;1,5\n")

        assert_includes get('/jeux/releves_sol').body, 'Reconnaître ses colonnes'
        parts = JSON.parse(post('/jeux/releves_sol/detecter', 'file' => 'mesures.csv', 'token' => 'secret').body)

        assert_empty parts['libres']
        assert_includes parts['colonnes'], '<code>valeur</code>'
        assert_includes parts['import'], CGI.escapeHTML('« mesures.csv » est lu.')

        assert_equal({ 'id' => 'text', 'valeur' => 'number' }, Sheet.load(@root.join('releves_sol')).tables.first.columns)
        refute_includes get('/jeux/releves_sol').body, 'Reconnaître ses colonnes'
      end

      def test_file_that_is_no_table_is_said_and_changes_nothing
        dataset('releves_sol', "id,value\nr1,1\n")

        assert_equal 422, put('/jeux/releves_sol/fichiers/notes.pdf', 'x', 'x-lexicon-token' => 'secret').status
        assert_includes put('/jeux/releves_sol/fichiers/vide.csv', '', 'x-lexicon-token' => 'secret').body, 'est vide'
        assert_equal SHEET, @root.join('releves_sol', Sheet::FILE).read
      end

      def test_name_that_is_wrong_or_taken_starts_nothing
        assert_equal 422, post('/jeux', 'name' => 'Relevés Sol', 'token' => 'secret').status
        assert_equal 422, post('/jeux', 'name' => '../ailleurs', 'token' => 'secret').status
        assert_includes post('/jeux', 'name' => 'prices', 'token' => 'secret').body, CGI.escapeHTML("Un jeu s'appelle déjà « prices »")
        assert_empty @root.children
      end

      def test_sheet_can_still_be_written_by_hand
        dataset('releves_sol', "id,value\nr1,douze\n")
        post('/jeux/releves_sol/fiche', 'sheet' => SHEET.sub('number', 'text'), 'token' => 'secret')

        assert_includes @root.join('releves_sol', Sheet::FILE).read, 'value: text'
      end

      def test_file_cannot_be_written_outside_its_dataset
        dataset('releves_sol', "id,value\nr1,1\n")
        put('/jeux/releves_sol/fichiers/..%2F..%2Fmal.csv', "id\nm1\n", 'x-lexicon-token' => 'secret')

        assert_equal 422, put('/jeux/releves_sol/fichiers/dataset.yml', 'x', 'x-lexicon-token' => 'secret').status
        assert_equal 404, put('/jeux/..%2Fautre/fichiers/a.csv', "id\nm1\n", 'x-lexicon-token' => 'secret').status
        assert_equal %w[releves_sol], @root.children.map { |child| child.basename.to_s }
        assert_equal %w[dataset.yml mal.csv releves.csv], @root.join('releves_sol').children.map { |child| child.basename.to_s }.sort
      end

      def test_nothing_changes_without_the_token_of_the_page
        dataset('releves_sol', "id,value\nr1,1\n")

        assert_equal 403, post('/jeux', 'name' => 'autre').status
        assert_equal 403, post('/jeux/releves_sol/fiche', 'sheet' => 'x', 'token' => 'faux').status
        assert_equal 403, put('/jeux/releves_sol/fichiers/a.csv', 'x').status
        assert_equal SHEET, @root.join('releves_sol', Sheet::FILE).read
      end

      def test_another_host_name_is_refused
        assert_equal 403, @app.call(request('GET', '/', '', 'host' => 'lexicon.example.org')).status
        assert_equal 200, @app.call(request('GET', '/', '', 'host' => '127.0.0.1:8787')).status
      end

      def test_read_only_directory_offers_the_review_only
        dataset('releves_sol', "id,value\nr1,1\n")
        FileUtils.chmod(0o555, @root)
        skip 'runs as root, for whom nothing is read-only' if @root.writable?

        assert_equal 403, post('/jeux', 'name' => 'autre', 'token' => 'secret').status
        refute_includes get('/jeux/releves_sol').body, '<form class="sheet"'
        assert_includes get('/jeux/releves_sol').body, 'Le jeu peut être proposé'
      end

      def test_fingerprint_changes_when_a_file_does
        dataset('releves_sol', "id,value\nr1,1\n")
        before = get('/jeux/releves_sol/empreinte').body
        @root.join('releves_sol', 'releves.csv').write("id,value\nr1,1\nr2,2\n")

        refute_equal before, get('/jeux/releves_sol/empreinte').body
      end

      def test_pages_are_served_over_http
        dataset('releves_sol', "id,value\nr1,1\n")
        port = TCPServer.open('127.0.0.1', 0) { |probe| probe.addr[1] }
        thread = Thread.new { Web::Server.new(@app, host: '127.0.0.1', port: port).run }
        sleep 0.2

        answer = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/jeux/releves_sol"))
        sent = Net::HTTP.start('127.0.0.1', port) do |http|
          http.send_request('PUT', '/jeux/releves_sol/fichiers/mesures.csv', "id\nm1\n", 'X-Lexicon-Token' => 'secret')
        end

        assert_equal '200', answer.code
        assert_includes answer.body.force_encoding('utf-8'), 'Le jeu peut être proposé'
        assert_equal '200', sent.code
        assert_equal "id\nm1\n", @root.join('releves_sol', 'mesures.csv').read
      ensure
        thread&.kill
      end

      private

        def dataset(name, csv, sheet: SHEET)
          @root.join(name).mkpath
          @root.join(name, Sheet::FILE).write(sheet)
          @root.join(name, 'releves.csv').write(csv)
        end

        def request(verb, path, body = '', headers = {})
          Web::App::Request.new(verb: verb, path: path, headers: { 'host' => 'localhost:8787' }.merge(headers), body: body)
        end

        def get(path)
          @app.call(request('GET', path))
        end

        def post(path, fields)
          @app.call(request('POST', path, URI.encode_www_form(fields), 'content-type' => 'application/x-www-form-urlencoded'))
        end

        def put(path, body, headers = {})
          @app.call(request('PUT', path, body, headers))
        end
    end
  end
end

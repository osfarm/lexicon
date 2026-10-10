# frozen_string_literal: true

require 'test_helper'

module Lexicon
  module Contribution
    class HostedTest < Minitest::Test
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
        @hosted = Web::Hosted.new(root: @root, secret: 'shared', prefix: '/contribute/outil', taken: %w[prices])
      end

      def teardown
        FileUtils.rm_rf(@root)
      end

      def test_only_the_api_is_answered
        assert_equal 403, ask('GET', '/', secret: 'wrong').status
        assert_equal 403, ask('GET', '/', secret: nil).status
        assert_equal 400, ask('GET', '/', workspace: '../other').status
        assert_equal 200, ask('GET', '/').status
        assert_raises(ArgumentError) { Web::Hosted.new(root: @root, secret: ' ', prefix: '') }
      end

      def test_any_host_name_is_answered_and_links_keep_the_prefix
        page = ask('GET', '/', host: 'lexicon.osfarm.org').body

        assert_includes page, 'contribuer, en ligne'
        assert_includes page, 'action="/contribute/outil/jeux"'
        assert_includes page, 'href="/contribute/outil/sortir"'

        created = ask('POST', '/jeux', form: { name: 'releves_sol', token: token_of(page) })

        assert_equal 303, created.status
        assert_equal '/contribute/outil/jeux/releves_sol', created.headers['Location']
        assert_includes ask('GET', '/').body, 'href="/contribute/outil/jeux/releves_sol"'
      end

      def test_each_key_has_its_own_datasets
        dataset('abcd1234', 'releves_sol', "id,value\nr1,12.5\n")

        assert_includes ask('GET', '/', workspace: 'abcd1234').body, 'jeux/releves_sol'
        refute_includes ask('GET', '/', workspace: 'wxyz9876').body, 'jeux/releves_sol'
        assert_equal 404, ask('GET', '/jeux/releves_sol', workspace: 'wxyz9876').status
        assert @root.join('wxyz9876').directory?
      end

      def test_an_accepted_dataset_is_proposed_from_its_page_and_can_be_withdrawn
        dir = dataset('abcd1234', 'releves_sol', "id,value\nr1,12.5\n")
        page = ask('GET', '/jeux/releves_sol').body

        assert_includes page, 'data-act="proposer"'

        ask('POST', '/jeux/releves_sol/proposer', token: token_of(page))

        assert_match(/\A\d{4}-\d{2}-\d{2}\n\z/, dir.join('proposed').read)
        assert_includes ask('GET', '/jeux/releves_sol').body, 'Jeu proposé le'
        assert_includes ask('GET', '/').body, 'proposé le'

        ask('POST', '/jeux/releves_sol/retirer', token: token_of(page))

        refute dir.join('proposed').exist?
      end

      def test_a_dataset_to_correct_is_not_proposed_and_a_change_needs_the_token_of_the_page
        dir = dataset('abcd1234', 'a_revoir', "id,value\nr1,douze\n")
        page = ask('GET', '/jeux/a_revoir').body

        refute_includes page, 'data-act="proposer"'
        ask('POST', '/jeux/a_revoir/proposer', token: token_of(page))
        refute dir.join('proposed').exist?

        File.write(dir.join('releves.csv'), "id,value\nr1,12\n")
        assert_equal 403, ask('POST', '/jeux/a_revoir/proposer', token: 'guessed').status
        refute dir.join('proposed').exist?
      end

      def test_proposing_is_not_offered_on_a_machine
        local = Web::App.new(root: @root.join('abcd1234').tap(&:mkpath), token: 'secret')
        dataset('abcd1234', 'releves_sol', "id,value\nr1,12.5\n")
        request = Web::App::Request.new(verb: 'POST', path: '/jeux/releves_sol/proposer', body: '',
                                        headers: { 'host' => 'localhost:8787', 'x-lexicon-token' => 'secret' })

        assert_equal 404, local.call(request).status
      end

      def test_a_maintainer_lists_what_is_proposed_and_brings_it_in
        dir = dataset('abcd1234', 'releves_sol', "id,value\nr1,12.5\n")
        dataset('abcd1234', 'brouillon', "id,value\nr1,1\n")
        dir.join('proposed').write("2026-10-10\n")
        inbox = Inbox.new(target: @root.to_s)
        contributions = Pathname.new(Dir.mktmpdir)

        assert_equal [{ workspace: 'abcd1234', name: 'releves_sol', proposed_on: '2026-10-10',
                        description: "Relevés d'humidité des sols", author: 'Camille Martin, GAEC des Prés' }], inbox.proposed

        fetched = inbox.fetch('abcd1234', 'releves_sol', into: contributions)

        assert_equal %w[dataset.yml releves.csv], fetched.children.map { |file| file.basename.to_s }.sort
        assert_raises(ArgumentError) { inbox.fetch('abcd1234', 'releves_sol', into: contributions) }
        assert_raises(ArgumentError) { inbox.fetch('..', 'releves_sol', into: contributions) }
        assert inbox.fetch('abcd1234', 'releves_sol', into: contributions, force: true).directory?
      ensure
        FileUtils.rm_rf(contributions) if contributions
      end

      private

        def dataset(workspace, name, csv)
          dir = @root.join(workspace, name)
          dir.mkpath
          dir.join(Sheet::FILE).write(SHEET)
          dir.join('releves.csv').write(csv)
          dir
        end

        def token_of(page)
          page[/data-token="([0-9a-f]+)"/, 1] || page[/name="token" value="([0-9a-f]+)"/, 1]
        end

        def ask(verb, path, secret: 'shared', workspace: 'abcd1234', host: 'contribute:8787', token: nil, form: nil)
          headers = { 'host' => host, Web::Hosted::WORKSPACE_HEADER => workspace }
          headers[Web::Hosted::SECRET_HEADER] = secret unless secret.nil?
          headers['x-lexicon-token'] = token unless token.nil?
          headers['content-type'] = 'application/x-www-form-urlencoded' unless form.nil?

          @hosted.call(Web::App::Request.new(verb: verb, path: path, headers: headers, body: form.nil? ? '' : URI.encode_www_form(form)))
        end
    end
  end
end

module Datasources
  class UserRoles < Base
    description 'User roles'
    credits name: 'Liste des roles de références', url: "https://ekylibre.com", provider: "Ekylibre SAS", licence: "CC-BY-SA 4.0", licence_url: "https://creativecommons.org/licenses/by-sa/4.0/deed.fr", updated_at: "2022-02-23"

    def collect
      FileUtils.cp Dir.glob('data/user_roles/user_roles - user_roles.csv'), dir
    end

    def load
      load_csv(dir.join('user_roles - user_roles.csv'), 'user_roles')
    end

    def self.table_definitions(builder)
      builder.table :master_user_roles, sql: <<~SQL
        CREATE TABLE master_user_roles (
          reference_name character varying PRIMARY KEY NOT NULL,
          accesses text[],
          translation_id character varying NOT NULL
        )
      SQL
    end

    def normalize
      query "DELETE FROM master_translations WHERE id LIKE 'user_roles%'"

      query <<-SQL
        INSERT INTO master_user_roles (reference_name, accesses, translation_id)
          SELECT reference_name, CONCAT('{', accesses, '}')::TEXT[], CONCAT('user_roles_', reference_name)
          FROM user_roles.user_roles
      SQL

      insert_translations('user_roles', 'user_roles', 'user_roles')
    end

  end
end

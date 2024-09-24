class Chef
  class Automate
    def self.is_installed?
      File.exist?('/hab/svc/automate-cs-oc-erchef/')
    end

    def self.config
      {
        sql_user: 'automate-cs-oc-erchef',
        sql_cert: '/hab/svc/automate-cs-oc-erchef/config/service.crt',
        sql_key: '/hab/svc/automate-cs-oc-erchef/config/service.key',
        sql_rootcert: '/hab/svc/automate-cs-oc-erchef/config/root_ca.crt',
        sql_db: 'automate-cs-oc-erchef',
        webui_key: '/hab/svc/automate-cs-oc-erchef/data/webui_priv.pem'
      }
    end
  end
end

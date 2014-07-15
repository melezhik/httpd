require 'chef/provider/lwrp_base'

class Chef
  class Provider
    class HttpdService
      class Rhel
        class Systemd < Chef::Provider::HttpdService::Rhel
          use_inline_resources if defined?(use_inline_resources)

          def whyrun_supported?
            true
          end

          action :create do
            #
            # local variables
            #
            case node['kernel']['machine']
            when 'x86_64'
              libarch = 'lib64'
            when 'i686'
              libarch = 'lib'
            end

            # enterprise linux version calculation
            case node['platform_version'].to_i
            when 5
              elversion = 5
            when 6
              elversion = 6
            when 2013
              elversion = 6
            when 2014
              elversion = 6
            end

            # version
            apache_version = new_resource.version

            # support multiple instances
            new_resource.name == 'default' ? apache_name = 'httpd' : apache_name = "httpd-#{new_resource.name}"

            # PID file
            case elversion
            when 5
              pid_file = "/var/run/#{apache_name}.pid"
            when 6
              pid_file = "/var/run/#{apache_name}/httpd.pid"
            end

            # lock file
            lock_file = "/var/lock/subsys/#{apache_name}"

            # apache 2.2 and 2.4 differences
            if apache_version.to_f < 2.4
              lock_file = "/var/lock/subsys/#{apache_name}"
              mutex = nil
            else
              lock_file = nil
              mutex = "file:/var/lock/subsys/#{apache_name} default"
            end

            # Include directories for additional configurtions
            if apache_version.to_f < 2.4
              includes = [
                'conf.d/*.conf',
                'conf.d/*.load'
              ]
            else
              include_optionals = [
                'conf.d/*.conf',
                'conf.modules.d/*.conf',
                'conf.modules.d/*.load'
              ]
            end

            #
            # Chef resources
            #

            # software installation
            package "#{new_resource.name} create #{new_resource.package_name}" do
              package_name new_resource.package_name
              notifies :run, "execute[#{new_resource.name} create remove_package_config]", :immediately
              action :install
            end

            execute "#{new_resource.name} create remove_package_config" do
              user 'root'
              command "rm -f /etc/#{apache_name}/conf.d/*"
              only_if "test -f /etc/#{apache_name}/conf.d/README"
              action :nothing
            end

            # modules
            %w( log_config logio unixd
              version watchdog
          ).each do |m|
              httpd_module m do
                httpd_version apache_version
                httpd_instance apache_name
                action :create
              end
            end

            if apache_version.to_f < 2.4
              # httpd binary symlinks
              link "#{new_resource.name} create /usr/sbin/#{apache_name}" do
                target_file "/usr/sbin/#{apache_name}"
                to '/usr/sbin/httpd'
                action :create
                not_if { apache_name == 'httpd' }
              end

              # MPM binaries
              link "#{new_resource.name} create /usr/sbin/#{apache_name}.worker" do
                target_file "/usr/sbin/#{apache_name}.worker"
                to '/usr/sbin/httpd.worker'
                action :create
                not_if { apache_name == 'httpd' }
              end

              link "#{new_resource.name} create /usr/sbin/#{apache_name}.event" do
                target_file "/usr/sbin/#{apache_name}.event"
                to '/usr/sbin/httpd.event'
                action :create
                not_if { apache_name == 'httpd' }
              end
            else
              httpd_module new_resource.mpm do
                action :install
              end
            end

            # configuration directories
            directory "#{new_resource.name} create /etc/#{apache_name}" do
              path "/etc/#{apache_name}"
              user 'root'
              group 'root'
              mode '0755'
              recursive true
              action :create
            end

            directory "#{new_resource.name} create /etc/#{apache_name}/conf" do
              path "/etc/#{apache_name}/conf"
              user 'root'
              group 'root'
              mode '0755'
              recursive true
              action :create
            end

            directory "#{new_resource.name} create /etc/#{apache_name}/conf.d" do
              path "/etc/#{apache_name}/conf.d"
              user 'root'
              group 'root'
              mode '0755'
              recursive true
              action :create
            end

            # support directories
            directory "#{new_resource.name} create /usr/#{libarch}/httpd/modules" do
              path "/usr/#{libarch}/httpd/modules"
              user 'root'
              group 'root'
              mode '0755'
              recursive true
              action :create
            end

            directory "#{new_resource.name} create /var/log/#{apache_name}" do
              path "/var/log/#{apache_name}"
              user 'root'
              group 'root'
              mode '0755'
              recursive true
              action :create
            end

            link "#{new_resource.name} create /etc/#{apache_name}/logs" do
              target_file "/etc/#{apache_name}/logs"
              to "../../var/log/#{apache_name}"
              action :create
            end

            link "#{new_resource.name} create /etc/#{apache_name}/modules" do
              target_file "/etc/#{apache_name}/modules"
              to "../../usr/#{libarch}/httpd/modules"
              action :create
            end

            # /var/run
            if elversion > 5
              directory "#{new_resource.name} create /var/run/#{apache_name}" do
                path "/var/run/#{apache_name}"
                user 'root'
                group 'root'
                mode '0755'
                recursive true
                action :create
              end

              link "#{new_resource.name} create /etc/#{apache_name}/run" do
                target_file "/etc/#{apache_name}/run"
                to "../../var/run/#{apache_name}"
                action :create
              end
            else
              link "#{new_resource.name} create /etc/#{apache_name}/run" do
                target_file "/etc/#{apache_name}/run"
                to '../../var/run/'
                action :create
              end
            end

            # configuration files
            template "#{new_resource.name} create /etc/#{apache_name}/conf/magic" do
              path "/etc/#{apache_name}/conf/magic"
              source 'magic.erb'
              owner 'root'
              group 'root'
              mode '0644'
              cookbook 'httpd'
              action :create
            end

            template "#{new_resource.name} create /etc/#{apache_name}/conf/httpd.conf" do
              path "/etc/#{apache_name}/conf/httpd.conf"
              source 'httpd.conf.erb'
              owner 'root'
              group 'root'
              mode '0644'
              variables(
                :config => new_resource,
                :server_root => "/etc/#{apache_name}",
                :error_log => "/var/log/#{apache_name}/error_log",
                :pid_file => pid_file,
                :lock_file => lock_file,
                :mutex => mutex,
                :includes => includes,
                :include_optionals => include_optionals
                )
              cookbook 'httpd'
              notifies :restart, "service[#{new_resource.name} create #{apache_name}]"
              action :create
            end

            #
            # SystemD
            #
            httpd_module 'systemd' do
              action :create
            end

            directory "#{new_resource.name} create /run/#{apache_name}" do
              path "/run/#{apache_name}"
              owner 'root'
              group 'apache'
              mode '0710'
              action :create
            end

            template "#{new_resource} create /usr/lib/systemd/system/#{apache_name}.service" do
              path "/usr/lib/systemd/system/#{apache_name}.service"
              source "#{apache_version}/systemd/#{node['platform']}/#{node['platform_version']}/httpd.service.erb"
              owner 'root'
              group 'root'
              mode '0644'
              cookbook 'httpd'
              variables(:apache_name => apache_name)
              action :create
            end

            directory "#{new_resource} create /usr/lib/systemd/system/#{apache_name}.service.d" do
              path "/usr/lib/systemd/system/#{apache_name}.service.d"
              owner 'root'
              group 'root'
              mode '0755'
              action :create
            end

            service "#{new_resource.name} create #{apache_name}" do
              service_name apache_name
              supports :restart => true, :reload => true, :status => true
              provider Chef::Provider::Service::Init::Systemd
              action [:start, :enable]
            end
          end

          action :delete do
            # support multiple instances
            new_resource.name == 'default' ? apache_name = 'httpd' : apache_name = "httpd-#{new_resource.name}"

            service "#{new_resource.name} create #{apache_name}" do
              supports :restart => true, :reload => true, :status => true
              provider Chef::Provider::Service::Init::Systemd
              action [:stop, :disable]
            end
          end

          action :restart do
            # support multiple instances
            new_resource.name == 'default' ? apache_name = 'httpd' : apache_name = "httpd-#{new_resource.name}"

            service "#{new_resource.name} delete #{apache_name}" do
              service_name apache_name
              supports :restart => true, :reload => true, :status => true
              provider Chef::Provider::Service::Init::Systemd
              action :restart
            end
          end

          action :reload do
            # support multiple instances
            new_resource.name == 'default' ? apache_name = 'httpd' : apache_name = "httpd-#{new_resource.name}"

            service "#{new_resource.name} delete #{apache_name}" do
              service_name apache_name
              supports :restart => true, :reload => true, :status => true
              provider Chef::Provider::Service::Init::Systemd
              action :reload
            end
          end
        end
      end
    end
  end
end
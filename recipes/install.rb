case node['platform']
when "ubuntu", "debian"
  include_recipe "apt"

  apt_repository "jenkins" do
    uri "#{node['jenkins']['package_url']}/debian"
    distribution 'binary/'
    key "http://pkg.jenkins-ci.org/debian/jenkins-ci.org.key"
    action :add
  end
when "centos", "redhat", "centos", "scientific", "amazon"
  include_recipe "yumrepo::jenkins"
end

#"jenkins stop" may (likely) exit before the process is actually dead
#so we sleep until nothing is listening on jenkins.server.port (according to netstat)
ruby_block "netstat" do
  block do
    10.times do
      if IO.popen("netstat -lnt").entries.select { |entry|
          entry.split[3] =~ /:#{node['jenkins']['server']['port']}$/
        }.size == 0
        break
      end
      Chef::Log.debug("service[jenkins] still listening (port #{node['jenkins']['server']['port']})")
      sleep 1
    end
  end
  action :nothing
end

service "jenkins" do
  supports [ :stop, :start, :restart, :status ]
  status_command "test -f #{node['jenkins']['pid_file']} && kill -0 `cat #{node['jenkins']['pid_file']}`"
  action :nothing
end

ruby_block "jenkins_block_until_operational" do
  block do
    until IO.popen("netstat -lnt").entries.select { |entry|
        entry.split[3] =~ /:#{node['jenkins']['server']['port']}$/
      }.size == 1
      Chef::Log.debug "service[jenkins] not listening on port #{node['jenkins']['server']['port']}"
      sleep 1
    end

    loop do
      url = URI.parse("#{node['jenkins']['server']['url']}/job/test/config.xml")
      res = Chef::REST::RESTRequest.new(:GET, url, nil).call
      break if res.kind_of?(Net::HTTPSuccess) or res.kind_of?(Net::HTTPNotFound) or res.kind_of?(Net::HTTPForbidden)
      Chef::Log.debug "service[jenkins] not responding OK to GET / #{res.inspect}"
      sleep 1
    end
  end
  action :nothing
end

package "jenkins" do
  notifies :start, "service[jenkins]", :immediately unless node['jenkins']['install_starts_service']
  notifies :create, "ruby_block[jenkins_block_until_operational]", :immediately
end

unless node['jenkins']['sysconf_template'].nil?
  template node['jenkins']['sysconf_template'] do
    notifies :restart, "service[jenkins]", :immediately
  end
end

# restart if this run only added new plugins
log "plugins updated, restarting jenkins" do
  #ugh :restart does not work, need to sleep after stop.
  notifies :stop, "service[jenkins]", :immediately
  notifies :create, "ruby_block[netstat]", :immediately
  notifies :start, "service[jenkins]", :immediately
  notifies :create, "ruby_block[jenkins_block_until_operational]", :immediately
  only_if do
    if File.exists?(node['jenkins']['pid_file'])
      htime = File.mtime(node['jenkins']['pid_file'])
      Dir["#{node['jenkins']['server']['home']}/plugins/*.hpi"].select { |file|
        File.mtime(file) > htime
      }.size > 0
    end
  end
  action :nothing
end

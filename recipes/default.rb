#
# Cookbook Name:: jenkins
# Based on hudson
# Recipe:: default
#
# Author:: AJ Christensen <aj@junglist.gen.nz>
# Author:: Doug MacEachern <dougm@vmware.com>
# Author:: Fletcher Nichol <fnichol@nichol.ca>
#
# Copyright 2010, VMware, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Install sshkey gem into chef
chef_gem "sshkey"

pkey = "#{node['jenkins']['server']['home']}/.ssh/id_rsa"
tmp = "/tmp"

user node['jenkins']['server']['user'] do
  home node['jenkins']['server']['home']
  shell "/bin/bash"
  system true
  uid node['jenkins']['server']['uid'] if node['jenkins']['server']['uid']
end

directory node['jenkins']['server']['home'] do
  recursive true
  owner node['jenkins']['server']['user']
  group node['jenkins']['server']['group']
end

directory "#{node['jenkins']['server']['home']}/.ssh" do
  mode 0700
  owner node['jenkins']['server']['user']
  group node['jenkins']['server']['group']
end

# Generate and deploy ssh public/private keys
Gem.clear_paths
require 'sshkey'
sshkey = SSHKey.generate(:type => 'RSA', :comment => "#{node['jenkins']['server']['user']}@#{node['fqdn']}")

# Save private key, unless pkey file exists
template pkey do
  owner node['jenkins']['server']['user']
  group node['jenkins']['server']['group']
  variables( :ssh_private_key => sshkey.private_key )
  mode 0600
  action :create_if_missing
end

# Template public key out to pkey.pub file
template "#{pkey}.pub" do
  owner node['jenkins']['server']['user']
  group node['jenkins']['server']['group']
  variables( :ssh_public_key => sshkey.ssh_public_key )
  mode 0644
  action :create_if_missing
end

ruby_block "store jenkins ssh pubkey" do
  block do
    node.set[:jenkins][:server][:pubkey] = File.read("#{pkey}.pub")
    node.save unless Chef::Config['solo']
  end
end

directory "#{node['jenkins']['server']['home']}/plugins" do
  owner node['jenkins']['server']['user']
  group node['jenkins']['server']['group']
  only_if { node['jenkins']['server']['plugins'].size > 0 }
end

node['jenkins']['server']['plugins'].each do |name|
  remote_file "#{node['jenkins']['server']['home']}/plugins/#{name}.hpi" do
    source "#{node['jenkins']['mirror']}/plugins/#{name}/latest/#{name}.hpi"
    backup false
    owner node['jenkins']['server']['user']
    group node['jenkins']['server']['group']
    action :create_if_missing
  end
end

include_recipe "java" if node['jenkins']['install_java']
include_recipe "jenkins::install"

# Front Jenkins with an HTTP server
case node['jenkins']['http_proxy']['variant']
when "nginx", "apache2"
  include_recipe "jenkins::proxy_#{node['jenkins']['http_proxy']['variant']}"
end

if node['jenkins']['iptables_allow'] == "enable"
  include_recipe "iptables"
  iptables_rule "port_jenkins" do
    if node['jenkins']['iptables_allow'] == "enable"
      enable true
    else
      enable false
    end
  end
end

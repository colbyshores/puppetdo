class String
  def colorize(color_code)
    "\e[#{color_code}m#{self}\e[0m"
  end

  def red
    colorize(31)
  end

  def green
    colorize(32)
  end

  def cyan
    colorize(36)
  end

  def yellow
    colorize(33)
  end
end

class Array
  def sort_by_number
    self.sort_by{|i|i.gsub(/\d+/) {|s| "%08d" % s.to_i }}
  end
end

module Puppetdo

  def Puppetdo.dhcpapi(hostquery)
    dhcpserver = $hiera.lookup("dhcpserver","/",$scope)
    domain = $hiera.lookup("domain","/",$scope)
    hosts = []
    content = open("http://#{dhcpserver}/rest/hostname/#{hostquery}").read

    #if explicitly defined due to numerical ordering
    if JSON.parse(content).count == 1
      hosts << JSON.parse(content)[0]["hostname"]
    else
      #otherwise isolate the cluster group based on its ending numerical value
      JSON.parse(content).each do |content|
        if content["hostname"] =~ /^#{hostquery}[\d+]\.#{domain}/
          hosts  << content["hostname"]
        end
      end
    end
    return hosts
  end

  def Puppetdo.dhcpapi_byip(ipaddress)
    dhcpserver = $hiera.lookup("dhcpserver","/",$scope)
    host = ''
    content = open("http://#{dhcpserver}/rest/ipaddress/#{ipaddress}").read
      JSON.parse(content).each do |content|
      if content["ipaddress"] =~ /^#{ipaddress}$/
        host  << content["hostname"]
        break
      end
    end
    return host
  end

  def Puppetdo.puppet(puppetquery)
    domain = $hiera.lookup("domain","/",$scope)
    #put a list if all certificate host names from the second column that starts with the API query followed by a number and followed by the primary domain in to a string array called certs...
    certs = `puppet cert list --all | awk '{ print $2 }' | egrep '^\"#{puppetquery}.#{domain}'`.delete('"').split(/\n/)
    if certs.count == 1
      return certs
    else
      return `puppet cert list --all | awk '{ print $2 }' | egrep '^\"#{puppetquery}[[:digit:]]+\.#{domain}'`.delete('"').split(/\n/)
    end
  end

  def Puppetdo.process(groupquery)
    $flag[:auditall] ? differences =  (Puppetdo.dhcpapi(groupquery) + Puppetdo.puppet(groupquery)).uniq.sort_by_number : differences =  (Puppetdo.dhcpapi(groupquery) - Puppetdo.puppet(groupquery)).sort_by_number
    if $flag[:audit] or $flag[:auditall]
       if differences.to_s != '' or $flag[:auditall]
         counter = 0
         differences.each do |host|
           Puppetdo.puppet(groupquery).include?(host) ? puppetresult = 'puppetcert->true'.green : puppetresult = 'puppetcert->false'.red
           Puppetdo.dhcpapi(groupquery).include?(host) ? dhcpresult = 'dhcp->true'.green : dhcpresult = 'dhcp->false'.red
           ping(host) ? pingresult = 'ping->true'.green : pingresult = 'ping->false'.red

           begin
             if host != Puppetdo.dhcpapi_byip(IPSocket.getaddress(host))
               ipaddress = "A->#{IPSocket.getaddress(host)}:DHCPMismatch".red
             else
               ipaddress = "A->#{IPSocket.getaddress(host)}".green
             end
           rescue
             ipaddress = "A->None".red
           end

           begin
             if Resolv.getname(IPSocket.getaddress(host)) != host
               reverse = "PTR->#{Resolv.getname(IPSocket.getaddress(host))}".red
             else
               reverse = "PTR->#{Resolv.getname(IPSocket.getaddress(host))}".green
             end
           rescue
             reverse = "PTR->None".yellow
           end

           puts "#{differences[counter]} = #{puppetresult}  #{dhcpresult}  #{pingresult}  #{ipaddress}  #{reverse}"
           counter += 1
         end
       end
    else
      processing(groupquery){ @commands }
    end
  end

  def Puppetdo.commands(commands)
    @commands = commands
  end
end


def processing(groupquery)
  hostlist = Puppetdo.puppet(groupquery).sort_by_number
  if hostlist.to_s != ''
    puts "Processing #{groupquery} hosts...\n"
    hostlist.each do |hostname|
      begin
        puts "starting... #{hostname}\n"
        ssh = Net::SSH.start(hostname, 'root', :paranoid => false)
        if $flag[:noop]
          sshcommand = "puppet agent --test --noop"
        else
          if !yield
            sshcommand = "puppet agent --test"
            res = ssh.exec!(sshcommand)
          else
            sshcommands = yield
            res = ''
            sshcommands.each do |command|
              begin
                res << ssh.exec!(command).green
              rescue
                res << "#{command} <- executed".cyan + "\n"
              end
            end
          end
        end
        ssh.close
        if $flag[:verbose] or $flag[:noop]
          puts res
        end
      rescue
        puts "Unable to connect to #{hostname}"
      end
      puts "finished... #{hostname}\n\n"
      sleep 1
    end
  end
  remove_instance_variable(:@commands)  #clear command buffer
  rescue
end

def ping(host, timeout=5, service="echo")
  begin
    timeout(timeout) do
      s = TCPSocket.new(host, service)
      s.close
    end
  rescue Errno::ECONNREFUSED
    return true
  rescue Timeout::Error, StandardError
    return false
  end
end

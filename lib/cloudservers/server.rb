module CloudServers
  class Server
    
    attr_reader   :id
    attr_reader   :name
    attr_reader   :status
    attr_reader   :progress
    attr_reader   :addresses
    attr_reader   :metadata
    attr_reader   :host_id
    attr_reader   :image_id
    attr_reader   :flavor_id
    attr_reader   :metadata
    attr_accessor :admin_pass
    
    # This class is the representation of a single Cloud Server object.  The constructor finds the server identified by the specified
    # ID number, accesses the API via the populate method to get information about that server, and returns the object.
    #
    # Will be called via the get_server or create_server methods on the CloudServers::Connection object, and will likely not be called directly.
    #
    #   >> server = cs.get_server(110917)
    #   => #<CloudServers::Server:0x1014e5438 ....>
    #   >> server.name
    #   => "RenamedRubyTest"
    def initialize( connection, id, url, data = nil )
      @connection    = connection
      @id            = id
      @url = url
      populate_with_hash( data ) if data
    end
    # ------------------------------------------------------------------- create
    def self.create( name, flavor, image, zone, connection = nil )
      data = { :name => name, :flavorRef => flavor.id, :imageRef  => image.id }
      connection ||= CloudServers::Connection.find_connection!
      path = connection.server_paths( zone ).first
      server_data = JSON.generate( :server => data )
      r = connection.csreq( 'POST', path.host, path.path, path.port, path.scheme, {}, server_data )
      response = JSON.parse( r.body )['server']
      l = URI.parse( response['links'].find{|x| x['rel'] == 'self'}['href'])
      new( connection, response['id'], l, response )
    end
    # -------------------------------------------------------------------- wait!
    def wait!( desired_status = 'ACTIVE', sleep_time = 20 )
      loop do
        refresh
        if self.status == desired_status
          break
        else
          yield( self ) if block_given?
          sleep( sleep_time )
        end
      end
    end
    # --------------------------------------------------------- change_password!
    def change_password!( new_pass = nil )
      if new_pass.nil?
        o =  [('0'..'9'), ('a'..'z'),('A'..'Z')].map{|i| i.to_a}.flatten
        new_pass = (0...15).map{ o[rand(o.length)] }.join;
      end
      data = { 'changePassword' => { 'adminPass' => new_pass } }
      response = @connection.csreq( "POST", @url.host, @url.path + '/action', @url.port, @url.scheme, {}, data.to_json )
      if response.is_a?( Net::HTTPSuccess )
        @admin_pass = new_pass
      else
        CloudServers::Exception.raise_exception(response)
      end
      
    end
    # ----------------------------------------------------------------- destroy!
    def destroy!( connection = nil )
      r = @connection.csreq( 'DELETE', @url.host, @url.path, @url.port, @url.scheme )
    end

    # --------------------------------------------------------------------- list
    def self.list( options = {}, connection = nil )
      connection ||= CloudServers::Connection.find_connection!
      servers = []
      connection.server_paths( options[:region] ) do |path|
        has_params = false
        [:name, :server, :status, :type].each do |x|
          next unless options[x]
          has_params = true
          param = "#{x}=#{options[x]}"
          if path.query
            path.query = [path.query, param ].join( '&' )
          else
            path.query = param
          end
        end
        r = connection.paginated_request( path )
        r['servers'].each do |data|
          if !block_given? || yield( data )
            link = if data['links']
              URI.parse( data['links'].first['href'] )
            else
              if has_params
                next unless options[:name].nil? || options[:name] == data['name']
              end
              x = URI.parse( path.to_s + "/#{data['id']}" )
            end
            servers << new( connection, data['id'], link, data )
          end
        end
      end
      return servers
    end
    
    # Makes the actual API call to get information about the given server object.  If you are attempting to track the status or project of
    # a server object (for example, when rebuilding, creating, or resizing a server), you will likely call this method within a loop until 
    # the status becomes "ACTIVE" or other conditions are met.
    #
    # Returns true if the API call succeeds.
    #
    #  >> server.refresh
    #  => true
    # ----------------------------------------------------------------- populate
    def populate
      response = @connection.csreq( "GET", @url.host, @url.path, @url.port, @url.scheme )
      CloudServers::Exception.raise_exception(response) unless response.code.match(/^20.$/)
      data = JSON.parse(response.body)["server"]
      @id        = data["id"]
      populate_with_hash( data )
      @populated = true
      true
    end

    # ------------------------------------------------------- populate_with_hash
    def populate_with_hash( data )
      @name      = data["name"]
      @status    = data["status"]
      @admin_pass    = data["adminPass"]
      @progress  = data["progress"]
      if data['addresses'] 
        @addresses = CloudServers.symbolize_keys(data["addresses"])
      end
      @metadata  = data["metadata"]
      @host_id    = data["hostId"]
      @image_id   = data["imageId"]
      @flavor_id  = data["flavorId"]
      @metadata  = data["metadata"]
    end
    alias :refresh :populate
    [ :progress, :addresses, :metadata, :host_id, :image_id, :flavor_id].each do |field|
      class_eval <<-EOS
        def #{field}
          populate unless @populated
          @#{field}
        end
      EOS
    end
    
    # Returns a new CloudServers::Flavor object for the flavor assigned to this server.
    #
    #   >> flavor = server.flavor
    #   => #<CloudServers::Flavor:0x1014aac20 @name="256 server", @disk=10, @id=1, @ram=256>
    #   >> flavor.name
    #   => "256 server"
    def flavor
      CloudServers::Flavor.new(@connection,self.flavorId)
    end
    
    # Returns a new CloudServers::Image object for the image assigned to this server.
    #
    #   >> image = server.image
    #   => #<CloudServers::Image:0x10149a960 ...>
    #   >> image.name
    #   => "Ubuntu 8.04.2 LTS (hardy)"
    def image
      CloudServers::Image.new(@connection,self.imageId)
    end
    
    # Sends an API request to reboot this server.  Takes an optional argument for the type of reboot, which can be "SOFT" (graceful shutdown)
    # or "HARD" (power cycle).  The hard reboot is also triggered by server.reboot!, so that may be a better way to call it.
    #
    # Returns true if the API call succeeds.
    #
    #   >> server.reboot
    #   => true
    def reboot(type="SOFT")
      data = JSON.generate(:reboot => {:type => type})
      response = @connection.csreq("POST",@svrmgmthost,"#{@svrmgmtpath}/servers/#{URI.encode(self.id.to_s)}/action",@svrmgmtport,@svrmgmtscheme,{'content-type' => 'application/json'},data)
      CloudServers::Exception.raise_exception(response) unless response.code.match(/^20.$/)
      true
    end
    
    # Sends an API request to hard-reboot (power cycle) the server.  See the reboot method for more information.
    #
    # Returns true if the API call succeeds.
    #
    #   >> server.reboot!
    #   => true
    def reboot!
      self.reboot("HARD")
    end
    
    # Updates various parameters about the server.  Currently, the only operations supported are changing the server name (not the actual hostname
    # on the server, but simply the label in the Cloud Servers API) and the administrator password (note: changing the admin password will trigger
    # a reboot of the server).  Other options are ignored.  One or both key/value pairs may be provided.  Keys are case-sensitive.
    #
    # Input hash key values are :name and :adminPass.  Returns true if the API call succeeds.
    #
    #   >> server.update(:name => "MyServer", :adminPass => "12345")
    #   => true
    #   >> server.name
    #   => "MyServer"
    def update(options)
      data = JSON.generate(:server => options)
      response = @connection.csreq("PUT",@svrmgmthost,"#{@svrmgmtpath}/servers/#{URI.encode(self.id.to_s)}",@svrmgmtport,@svrmgmtscheme,{'content-type' => 'application/json'},data)
      CloudServers::Exception.raise_exception(response) unless response.code.match(/^20.$/)
      # If we rename the instance, repopulate the object
      self.populate if options[:name]
      true
    end
    
    # Deletes the server from Cloud Servers.  The server will be shut down, data deleted, and billing stopped.
    #
    # Returns true if the API call succeeds.
    #
    #   >> server.delete!
    #   => true
    def delete!
      response = @connection.csreq("DELETE",@svrmgmthost,"#{@svrmgmtpath}/servers/#{URI.encode(self.id.to_s)}",@svrmgmtport,@svrmgmtscheme)
      CloudServers::Exception.raise_exception(response) unless response.code.match(/^20.$/)
      true
    end
    
    # Takes the existing server and rebuilds it with the image identified by the imageId argument.  If no imageId is provided, the current image
    # will be used.
    #
    # This will wipe and rebuild the server, but keep the server ID number, name, and IP addresses the same.
    #
    # Returns true if the API call succeeds.
    #
    #   >> server.rebuild!
    #   => true
    def rebuild!(imageId = self.imageId)
      data = JSON.generate(:rebuild => {:imageId => imageId})
      response = @connection.csreq("POST",@svrmgmthost,"#{@svrmgmtpath}/servers/#{URI.encode(self.id.to_s)}/action",@svrmgmtport,@svrmgmtscheme,{'content-type' => 'application/json'},data)
      CloudServers::Exception.raise_exception(response) unless response.code.match(/^20.$/)
      self.populate
      true
    end
    
    # Takes a snapshot of the server and creates a server image from it.  That image can then be used to build new servers.  The
    # snapshot is saved asynchronously.  Check the image status to make sure that it is ACTIVE before attempting to perform operations
    # on it.
    # 
    # A name string for the saved image must be provided.  A new CloudServers::Image object for the saved image is returned.
    #
    # The image is saved as a backup, of which there are only three available slots.  If there are no backup slots available, 
    # A CloudServers::Exception::CloudServersFault will be raised.
    #
    #   >> image = server.create_image("My Rails Server")
    #   => 
    def create_image(name)
      data = JSON.generate(:image => {:serverId => self.id, :name => name})
      response = @connection.csreq("POST",@svrmgmthost,"#{@svrmgmtpath}/images",@svrmgmtport,@svrmgmtscheme,{'content-type' => 'application/json'},data)
      CloudServers::Exception.raise_exception(response) unless response.code.match(/^20.$/)
      CloudServers::Image.new(@connection,JSON.parse(response.body)['image']['id'])
    end
    
    # Resizes the server to the size contained in the server flavor found at ID flavorId.  The server name, ID number, and IP addresses 
    # will remain the same.  After the resize is done, the server.status will be set to "VERIFY_RESIZE" until the resize is confirmed or reverted.
    #
    # Refreshes the CloudServers::Server object, and returns true if the API call succeeds.
    # 
    #   >> server.resize!(1)
    #   => true
    def resize!(flavorId)
      data = JSON.generate(:resize => {:flavorId => flavorId})
      response = @connection.csreq("POST",@svrmgmthost,"#{@svrmgmtpath}/servers/#{URI.encode(self.id.to_s)}/action",@svrmgmtport,@svrmgmtscheme,{'content-type' => 'application/json'},data)
      CloudServers::Exception.raise_exception(response) unless response.code.match(/^20.$/)
      self.populate
      true
    end
    
    # After a server resize is complete, calling this method will confirm the resize with the Cloud Servers API, and discard the fallback/original image.
    #
    # Returns true if the API call succeeds.
    #
    #   >> server.confirm_resize!
    #   => true
    def confirm_resize!
      # If the resize bug gets figured out, should put a check here to make sure that it's in the proper state for this.
      data = JSON.generate(:confirmResize => nil)
      response = @connection.csreq("POST",@svrmgmthost,"#{@svrmgmtpath}/servers/#{URI.encode(self.id.to_s)}/action",@svrmgmtport,@svrmgmtscheme,{'content-type' => 'application/json'},data)
      CloudServers::Exception.raise_exception(response) unless response.code.match(/^20.$/)
      self.populate
      true
    end
    
    # After a server resize is complete, calling this method will reject the resized server with the Cloud Servers API, destroying
    # the new image and replacing it with the pre-resize fallback image.
    #
    # Returns true if the API call succeeds.
    #
    #   >> server.confirm_resize!
    #   => true
    def revert_resize!
      # If the resize bug gets figured out, should put a check here to make sure that it's in the proper state for this.
      data = JSON.generate(:revertResize => nil)
      response = @connection.csreq("POST",@svrmgmthost,"#{@svrmgmtpath}/servers/#{URI.encode(self.id.to_s)}/action",@svrmgmtport,@svrmgmtscheme,{'content-type' => 'application/json'},data)
      CloudServers::Exception.raise_exception(response) unless response.code.match(/^20.$/)
      self.populate
      true
    end
    
    # Provides information about the backup schedule for this server.  Returns a hash of the form 
    # {"weekly" => state, "daily" => state, "enabled" => boolean}
    #
    #   >> server.backup_schedule
    #   => {"weekly"=>"THURSDAY", "daily"=>"H_0400_0600", "enabled"=>true}
    def backup_schedule
      response = @connection.csreq("GET",@svrmgmthost,"#{@svrmgmtpath}/servers/#{URI.encode(@id.to_s)}/backup_schedule",@svrmgmtport,@svrmgmtscheme)
      CloudServers::Exception.raise_exception(response) unless response.code.match(/^20.$/)
      JSON.parse(response.body)['backupSchedule']
    end
    
    # Updates the backup schedule for the server.  Takes a hash of the form: {:weekly => state, :daily => state, :enabled => boolean} as an argument.
    # All three keys (:weekly, :daily, :enabled) must be provided or an exception will get raised.
    #
    #   >> server.backup_schedule=({:weekly=>"THURSDAY", :daily=>"H_0400_0600", :enabled=>true})
    #   => {:weekly=>"THURSDAY", :daily=>"H_0400_0600", :enabled=>true}
    def backup_schedule=(options)
      data = JSON.generate('backupSchedule' => options)
      response = @connection.csreq("POST",@svrmgmthost,"#{@svrmgmtpath}/servers/#{URI.encode(self.id.to_s)}/backup_schedule",@svrmgmtport,@svrmgmtscheme,{'content-type' => 'application/json'},data)
      CloudServers::Exception.raise_exception(response) unless response.code.match(/^20.$/)
      true
    end
    
    # Removes the existing backup schedule for the server, setting the backups to disabled.
    #
    # Returns true if the API call succeeds.
    #
    #   >> server.disable_backup_schedule!
    #   => true
    def disable_backup_schedule!
      response = @connection.csreq("DELETE",@svrmgmthost,"#{@svrmgmtpath}/servers/#{URI.encode(self.id.to_s)}/backup_schedule",@svrmgmtport,@svrmgmtscheme)
      CloudServers::Exception.raise_exception(response) unless response.code.match(/^20.$/)
      true
    end

    # Share IP between servers in Shared IP group.
    # Takes a hash of the form: {:sharedIpGroupId => "1234", :ipAddress => "67.23.10.132", :configureServer => false} as an argument.
    # The :sharedIpGroupId key is required.
    # The :ipAddress key is required.
    # The :configureServer key is optional and defaults to false.
    #
    #   >> server.share_ip(:sharedIpGroupId => 100, :ipAddress => "67.23.10.132")
    #   => true
    def share_ip(options)
      raise CloudServers::Exception::MissingArgument, "Shared IP Group ID must be supplied" unless options[:sharedIpGroupId]
      raise CloudServers::Exception::MissingArgument, "Ip Address must be supplied" unless options[:ipAddress]
      options[:configureServer] = false if options[:configureServer].nil?
      data = JSON.generate(:shareIp => {:sharedIpGroupId => options[:sharedIpGroupId], :configureServer => options[:configureServer]})
      response = @connection.csreq("PUT",@svrmgmthost,"#{@svrmgmtpath}/servers/#{URI.encode(self.id.to_s)}/ips/public/#{options[:ipAddress]}",@svrmgmtport,@svrmgmtscheme,{'content-type' => 'application/json'},data)
      CloudServers::Exception.raise_exception(response) unless response.code.match(/^20.$/)
      true
    end

    # Unshare an IP address.
    # Takes a hash of the form: {:ipAddress => "67.23.10.132"} as an argument.
    # The :ipAddress key is required.
    #
    #   >> server.unshare_ip(:ipAddress => "67.23.10.132")
    #   => true
    def unshare_ip(options)
      raise CloudServers::Exception::MissingArgument, "Ip Address must be supplied" unless options[:ipAddress]
      response = @connection.csreq("DELETE",@svrmgmthost,"#{@svrmgmtpath}/servers/#{URI.encode(self.id.to_s)}/ips/public/#{options[:ipAddress]}",@svrmgmtport,@svrmgmtscheme)
      CloudServers::Exception.raise_exception(response) unless response.code.match(/^20.$/)
      true
    end
 
  end
end

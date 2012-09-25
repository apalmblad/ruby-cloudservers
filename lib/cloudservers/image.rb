module CloudServers
  class Image

    attr_reader :id
    attr_reader :name
    attr_reader :populated
    
    # This class provides an object for the "Image" of a server.  The Image refers to the Operating System type and version.
    #
    # Returns the Image object identifed by the supplied ID number.  Called from the get_image instance method of CloudServers::Connection,
    # it will likely not be called directly from user code.
    #
    #   >> cs = CloudServers::Connection.new(USERNAME,API_KEY)
    #   >> image = cs.get_image(2)
    #   => #<CloudServers::Image:0x1015371c0 ...>
    #   >> image.name
    #   => "CentOS 5.2"    
    def initialize( connection, id, link, extra_data = nil )
      @id = id
      @connection = connection
      @populated = false
      @link = link
      populate_from_hash( extra_data ) if extra_data
      #populate( link )
    end

    [ :serverId, :updated, :created, :status, :progress].each do |field|
      class_eval <<-EOS
        def #{field}
          populate unless @populated
          @#{field}
        end
      EOS
    end


    
    # Makes the HTTP call to load information about the provided image.  Can also be called directly on the Image object to refresh data.
    # Returns true if the refresh call succeeds.
    #
    #   >> image.populate
    #   => true
    def populate
      response = @connection.csreq( "GET", @link.host, @link.path, @link.port, @link.scheme )
      CloudServers::Exception.raise_exception(response) unless response.code.match(/^20.$/)
      data = JSON.parse(response.body)['image']
      populate_from_hash( data )
      @id = data['id']
      @populated = true
      return true
    end
    # ------------------------------------------------------- populate_from_hash
    def populate_from_hash( data )
      @name = data['name']
      @serverId = data['serverId']
      @updated = DateTime.parse(data['updated']) if data['updated']
      @created = DateTime.parse(data['created']) if data['created']
      @status = data['status']
      @progress = data['progress']
    end
    alias :refresh :populate
    
    # Delete an image.  This should be returning invalid permissions when attempting to delete system images, but it's not.
    # Returns true if the deletion succeeds.
    #
    #   >> image.delete!
    #   => true
    def delete!
      response = @connection.csreq("DELETE",@connection.svrmgmthost,"#{@connection.svrmgmtpath}/images/#{URI.escape(self.id.to_s)}",@connection.svrmgmtport,@connection.svrmgmtscheme)
      CloudServers::Exception.raise_exception(response) unless response.code.match(/^20.$/)
      true
    end
    # --------------------------------------------------------------------- list
    def self.list( options = {}, connection = nil )
      connection ||= CloudServers::Connection.find_connection!
      images = []
      paths = connection.image_paths( options[:region] )
      raise "No paths found in #{options[:region]}" if paths.empty?
      paths.each do |path|
        [:name, :server, :status, :type].each do |x|
          next unless options[x]
          param = "#{x}=#{options[x]}"
          if path.query
            path.query = [path.query, param ].join( '&' )
          else
            path.query = param
          end
        end
        r = connection.paginated_request( path )
        r['images'].each do |data|
          if !block_given? || yield( data )
            link = if data['links']
              URI.parse( data['links'].find{ |x| x['rel'] == 'self' }['href'] )
            else
              URI.parse( path.to_s + "/#{data['id']}" )
            end
            im = new( connection, data['id'], link, data )
            images <<  im
          end
        end
      end
      return images
    end
    
  end
end

module CloudServers
  class Flavor
  
    attr_reader :id
    attr_reader :name
    attr_reader :ram
    attr_reader :disk

    # This class provides an object for the "Flavor" of a server.  The Flavor can generally be taken as the server specification,
    # providing information on things like memory and disk space.
    #
    # The disk attribute is an integer representing the disk space in GB.  The memory attribute is an integer representing the RAM in MB.
    #
    # This is called from the get_flavor method on a CloudServers::Connection object, returns a CloudServers::Flavor object, and will likely not be called directly.
    #
    #   >> flavor = cs.get_flavor(1)
    #   => #<CloudServers::Flavor:0x1014f8bc8 @name="256 server", @disk=10, @id=1, @ram=256>
    #   >> flavor.name
    #   => "256 server"
    def initialize( connection, id, link )
      response = connection.csreq( "GET", link.host, link.path, link.port, link.scheme )
      CloudServers::Exception.raise_exception(response) unless response.code.match(/^20.$/)
      data = JSON.parse(response.body)['flavor']
      @id   = data['id']
      @name = data['name']
      @ram  = data['ram']
      @disk = data['disk']
    end
    # --------------------------------------------------------------------- list
    def self.list( options = {}, connection = nil )
      connection ||= CloudServers::Connection.find_connection!
      flavors = []
      connection.flavor_paths( options[:region] ) do |path|
        r = connection.paginated_request( path )
        r['flavors'].each do |data|
          if !block_given? || yield( data )
            link = data['links'].find{ |x| x['rel'] == 'self' }['href']
            flavors << new( connection, data['id'], URI.parse( link ) )
          end
        end
      end
      return flavors
    end
    
  end
end

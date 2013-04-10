class CloudServers::Volume < Struct.new( :name, :id, :size, :created, :updated, :description )
  attr_reader :connection
  attr_accessor :base_path
  # ----------------------------------------------------------------- initialize
  def initialize( connection, id, name, description, size, created )
    @connection = connection
    self.id = id
    self.name = name
    self.description = description
    self.size = size
    self.created = created
  end
  # ----------------------------------------------------------------------- list
  def self.list( connection = nil )
    connection ||= CloudServers::Connection.find_connection!
    volumes = []
    connection.volume_paths do |path, region|
      r = connection.csreq( 'GET', path.host, "#{path.path}/volumes", path.port, path.scheme )
      case r.code.to_i
      when 200
        body = JSON.parse( r.body )
        next if body['volumes'].empty?
        body['volumes'].each do |vol|
          v = new( connection,
                   vol.delete( 'id' ),
                   vol.delete( 'display_name' ),
                   vol.delete( 'display_description' ),
                   vol.delete( 'size' ).to_i,
                   vol.delete( 'createdAt' ) )

          v.base_path = path
          volumes << v
        end
      else
        CloudServers::Exception.raise_exception( r ) 
      end
    end
    return volumes
  end
  # ------------------------------------------------------------------ snapshot!
  def snapshot!( name )
    data = { 'snapshot' => { 'display_name' => name, 'volume_id' => id, 'force' => true } }
    r = connection.csreq( 'POST', base_path.host, File.join( base_path.path, 'snapshots' ), base_path.port, base_path.scheme, {}, data.to_json )
    unless r.code =~ /20\d/
      CloudServers::Exception.raise_exception( r )
    end
    return r
  end
  # ------------------------------------------------------------------ snapshots
  def snapshots
    r = connection.csreq( 'GET', base_path.host, File.join( base_path.path, 'snapshots' ), base_path.port, base_path.scheme )
    data = JSON.parse( r.body )
    data['snapshots'].find_all do |x|
      x['volume_id'] == id
    end
  end
end

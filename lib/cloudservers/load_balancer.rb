class CloudServers::LoadBalancer < Struct.new( :name, :id, :created, :updated )
  attr_accessor :protocol
  attr_accessor :port
  attr_reader :algorithm
  attr_reader :status
  attr_reader :region
  attr_reader :connection

  API_SERVER = 'dns.api.rackspacecloud.com'
  # ----------------------------------------------------------------- initialize
  def initialize( connection, status, region )
    @connection = connection
    @status = status
    @region = region
  end
  def details

  end
  ALLOWED_ALGORITHMS = 'RANDOM', 'WEIGHTED_LEAST_CONNECTIONS', 'WEIGHTED_ROUND_ROBIN'
  # ----------------------------------------------------------------- algorithm=
  def algorithm=( a )
    raise "Invalid algorithm: #{a}!" unless ALLOWED_ALGORITHMS.include?( a )
    @algorithm = a
  end
  # ------------------------------------------------------------------ weighted?
  def weighted?
    ['WEIGHTED_LEAST_CONNECTIONS', 'WEIGHTED_ROUND_ROBIN'].include?( algorithm)
  end
  # ------------------------------------ make_request( request_method, path_part
  def make_request( request_method, path_part, headers = {}, data = nil )
    path = @connection.load_balancer_paths( region ).first
    r = @connection.csreq( request_method, path.host, "#{path.path}#{path_part}", path.port, path.scheme, headers, data )
    unless r.code =~ /20\d/
      CloudServers::Exception.raise_exception( r )
    end
    return r
  end
  # -------------------------------------------------------------------- stats
  def stats
    r = make_request( 'GET', "/loadbalancers/#{id}/stats" )
    JSON.parse( r.body )
  end
  # -------------------------------------------------------------------- details
  def details
    r = make_request( 'GET', "/loadbalancers/#{id}" )
    JSON.parse( r.body )
  end
  # ---------------------------------------------------------------------- nodes
  def nodes
    @nodes ||= begin
      r = make_request( 'GET', "/loadbalancers/#{id}/nodes" )
      body = JSON.parse( r.body )
      body['nodes'].map do |node|
        n = Node.new( self, node.delete( 'status' ) )
        n.attributes= node
        n
      end
    end
    
  end

  # ----------------------------------------------------------------------- list
  def self.list( connection = nil )
    connection ||= CloudServers::Connection.find_connection!
    load_balancers = []
    connection.load_balancer_paths do |path, region|
      r = connection.csreq( 'GET', path.host, "#{path.path}/loadbalancers", path.port, path.scheme )
      case r.code.to_i
      when 200
        body = JSON.parse( r.body )
        next if body['loadBalancers'].empty?
        body['loadBalancers'].each do |lb|
          lb.delete( 'nodeCount' )
          l = new( connection, lb.delete( 'status' ), region )
          lb.delete( 'virtualIps' ).each { |x| l.virtual_ips << VirtualIp.from_hash( x ) }
          l.attributes = lb
          load_balancers << l
        end
      else
        CloudServers::Exception.raise_exception( response ) 
      end
    end
    return load_balancers
  end
  # ---------------------------------------------------------------- virtual_ips
  def virtual_ips
    @virtual_ips ||= []
    @virtual_ips 
  end
  # ---------------------------------------------------------------- attributes=
  def attributes=( attrs )
    attrs.each_pair do |k,v|
      if respond_to?( "#{k}=" )
        send( "#{k}=", v )
      else
        raise "Unknown attribute: #{k}"
      end
    end
  end
  class VirtualIp < Struct.new( :id, :address, :type, :ipversion )
    def self.from_hash( h )
      new( h['id'], h['address'], h['type'], h['ipVersion']  )

    end
  end
  class Node
    attr_accessor :address
    attr_accessor :id
    attr_accessor :port
    attr_reader :type
    attr_reader :weight
    attr_reader :condition
    attr_reader :load_balancer
   
    def initialize( load_balancer, status  )
      @load_balancer = load_balancer
      @status = status
    end
    VALID_TYPES = %w(PRIMARY SECONDARY)
    def type=(t )
      raise "Invalid type: #{t}" unless VALID_TYPES.include?( t )
      @type = t
    end
     
    # ----------------------------------------------------------------- weight=
    def weight=( w )
      raise "Load balancer does not support weight!" unless load_balancer.weighted?
      w = w.to_i
      raise "Invalid node weight: #{w}" if w > 100 || w < 1
      @weight = w
    end
    VALID_CONDITIONS = %w(ENABLED DISABLED DRAINING)
    def condition=( c )
      raise "Invalid condition: #{c}" unless VALID_CONDITIONS.include?( c )
      @condition = c
    end
    def to_hash
      r_val = {}
      r_val['condition'] = condition if condition
      r_val['type'] = type if type
      r_val['weight'] = weight if weight && load_balancer.weighted?
      return r_val
    end
    # ------------------------------------------------------------------ disable
    def disable
      self.condition = 'DISABLED'
    end
    # ------------------------------------------------------------------ disable
    def enable
      self.condition = 'ENABLED'
    end
    # -------------------------------------------------------------------- save!
    def save!
      r = load_balancer.make_request( 'PUT', "/loadbalancers/#{load_balancer.id}/nodes/#{id}", {}, to_hash.to_json)
      if r.code =~ /20\d/
        return true
      else
        CloudServers::Exception.raise_exception( r ) 
      end

    end
    # -------------------------------------------------------------- attributes=
    def attributes=( attrs )
      attrs.each_pair do |k,v|
        if respond_to?( "#{k}=" )
          send( "#{k}=", v )
        else
          raise "Unknown attribute: #{k}"
        end
      end
    end
  end

end

class CloudServers::LoadBalancer < Struct.new( :name, :id, :created, :updated )
  attr_accessor :protocol
  attr_accessor :port
  attr_accessor :is_public
  attr_reader :algorithm
  attr_reader :status
  attr_accessor :region
  attr_reader :connection

  API_SERVER = 'dns.api.rackspacecloud.com'
  # ----------------------------------------------------------------- initialize
  def initialize( connection = nil, id = nil, url = nil, data = nil )
    connection ||= CloudServers::Connection.find_connection!
    @connection = connection
    @status = status
    @url = url
    if @url
      @region = @url.host[0..2].upcase
    end
    self.id = id
    populate_with_hash( data ) if data
  end
  # ---------------------------------------------------------------------- nodes
  def nodes
    if @nodes.nil?
      details
    end
    @nodes
  end
  # --------------------------------------------------------- populate_with_hash
  def populate_with_hash( data )
    self.id = data['id'] unless id
    self.name = data['name'] if data['name']
    @protocol = data['protocol'] if data['protocol']
    @port = data['port'] if data['port']
    @algorithm = data['algorithm'] if data['algorithm']
    @status = data['status'] if data['status']
    if data['connectionLogging']
      @connection_logging = data['connectionLogging']['enabled']
    end
    if data['nodes']
      @nodes = data['nodes'].map do |x|
        Node.new( self, x['status'], x )
      end 
    end
  end


  VALID_PROTOCOLS = {"DNS_TCP" => "53", "DNS_UDP" =>"53", "FTP" =>"21",
    "HTTP" =>"80", "HTTPS" => "443", "IMAPS" => "993", "IMAPv4" => "143",
    "LDAP" => "389", "LDAPS" => "636", "MYSQL" => "3306", "POP3" => "110",
    "POP3S" => "995", "SMTP" => "25" , "TCP"  => "0", "TCP_CLIENT_FIRST" => "0",
    "UDP"  => "0" , "UDP_STREAM"  => "0" , "SFTP"  => "22" }
  # ------------------------------------------------------------------ protocol=
  def protocol=( p )
    p = p.upcase
    if VALID_PROTOCOLS[p]
      @protocol = p
      @port = VALID_PROTOCOLS[p] if @port.nil?
    end
  end
  # --------------------------------------------------------------------- create
  def create
    raise "Missing protocol" if @protocol.nil?
    raise "Missing name" if name.nil?
    raise "No nodes!" if @nodes.nil? || @nodes.empty?
    raise 'No Region!' if @region.nil?
    data = {'name' => name, 'protocol' => @protocol, 'nodes' => @nodes,
        'virtualIps' => [{'type' => (@is_public || @is_public.nil?) ? 'PUBLIC' : 'SERVICENET'}] }
    r = make_request( 'POST', "/loadbalancers", {}, { 'loadBalancer' => data }.to_json)
    details = JSON.parse( r.body )['loadBalancer']
    self.id = details['id'].to_i
    path = @connection.load_balancer_paths( region ).first
    @url = URI.parse( "#{path.to_s}/loadbalancers/#{id}" )
    populate_with_hash( details )
  end

  ALLOWED_ALGORITHMS = 'RANDOM', 'WEIGHTED_LEAST_CONNECTIONS', 'WEIGHTED_ROUND_ROBIN'
  # ----------------------------------------------------------------- algorithm=
  def algorithm=( a )
    raise "Invalid algorithm: #{a}!" unless ALLOWED_ALGORITHMS.include?( a )
    @algorithm = a
  end
  # ------------------------------------------------------------------- add_node
  def add_node( address, port, type = nil, condition= 'ENABLED')
    @nodes ||= []
    data =  {  'address' => address,
               'port' => port,
               'type' => type || 'PRIMARY',
               'condition' => condition }
    if id
      make_request( 'POST', "/loadbalancers/#{id}/nodes", {}, { 'nodes' => [data] }.to_json)
      details
    else
      @nodes << data
    end
  end
  # --------------------------------------------------------------------- remove
  def remove
    r = @connection.csreq( 'DELETE', @url.host, @url.path, @url.port, @url.scheme )
    CloudServers::Exception.raise_exception(r) unless r.code.match(/^20.$/)
    true
  end
  # ----------------------------------------------------------- wait_until_ready
  def wait_until_ready( sleep_time = 10 )
    while ['PENDING_UPDATE', 'BUILD'].include?( status  )
      sleep( sleep_time )
      details
    end
  end
  # ------------------------------------------------------------------ weighted?
  def weighted?
    ['WEIGHTED_LEAST_CONNECTIONS', 'WEIGHTED_ROUND_ROBIN'].include?( algorithm)
  end
  # --------------------------------------------------------------- make_request
  def make_request( request_method, path_part, headers = {}, data = nil )
    path = @connection.load_balancer_paths( region ).first
    r = @connection.csreq( request_method,
                           path.host,
                           "#{path.path}#{path_part}",
                           path.port,
                           path.scheme,
                           headers,
                           data )
    unless r.code =~ /20\d/
      CloudServers::Exception.raise_exception( r )
    end
    return r
  end
  # -------------------------------------------------------------------- stats
  def stats
    r = make_request( 'GET', "/loadbalancers/#{id}/stats" )
    unless r.code =~ /20\d/
      CloudServers::Exception.raise_exception( r )
    end
    JSON.parse( r.body )
  end
  # -------------------------------------------------------------------- details
  def details
    r = make_request( 'GET', "/loadbalancers/#{id}" )
    unless r.code =~ /20\d/
      CloudServers::Exception.raise_exception( r )
    end
    data = JSON.parse( r.body )
    populate_with_hash( data['loadBalancer'] )
    return data
  end
  # ------------------------------------------------------------------- block_ip
  def block_ip( ip_addr )
    block_ips( [ip_addr] )
  end
  # ------------------------------------------------------------------ block_ips
  def block_ips( ip_list )
    ip_list = ip_list.map{ |x| { 'address' => x, 'type' => 'DENY' } }
    payload = { 'accessList' => ip_list }
    r = make_request( 'POST', "/loadbalancers/#{id}/accesslist", {}, payload.to_json )
  end
  # ----------------------------------------------------------------- unblock_ip
  def unblock_ip( ip_addr )
    to_unblock = blocked_ips.find{ |x| x['address'] == ip_addr }
    if to_unblock && to_unblock['id']
      make_request( 'DELETE', "/loadbalancers/#{id}/accesslist/#{to_unblock['id']}" )
    end
  end
  # ----------------------------------------------------------------- unblock_ip
  def unblock_acl_ids( id_list )
    id_list.each_slice( 10 ) do |ids|
      list = ids.map{ |x| "id=#{x}" }.join('&')
      make_request( 'DELETE', "/loadbalancers/#{id}/accesslist?#{list}" )
      wait_until_ready( 5 )
    end
  end
  # ---------------------------------------------------------------- blocked_ips
  def blocked_ips
    access_list.find_all{ |x| x['type'] == 'DENY' }
  end
  # ---------------------------------------------------------------- access_list
  def access_list
    r = make_request( 'GET', "/loadbalancers/#{id}/accesslist" )
    CloudServers::Exception.raise_exception( r ) unless r.code =~ /20\d/
    data = JSON.parse( r.body )
    return data['accessList'] || []
  end
  # ---------------------------------------------------------------------- nodes
  #def nodes
  #  @nodes ||= begin
  #    r = make_request( 'GET', "/loadbalancers/#{id}/nodes" )
  #    body = JSON.parse( r.body )
  #     body['nodes'].map do |node|
  #      n = Node.new( self, node.delete( 'status' ) )
  #      n.attributes= node
  #      n
  #    end
  #  end
  #  
  #end

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
          url =URI.parse( path.to_s + '/loadbalancers/' + lb['id'].to_s )
          l = new( connection, lb.delete( 'id' ), url, lb )
          lb.delete( 'virtualIps' ).each { |x| l.virtual_ips << VirtualIp.from_hash( x ) }
          load_balancers << l
        end
      else
        CloudServers::Exception.raise_exception( r ) 
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
   
    # --------------------------------------------------------------- initialize
    def initialize( load_balancer, status, data = nil  )
      @load_balancer = load_balancer
      @status = status
      populate_from_hash( data) if data
    end
    # ------------------------------------------------------- populate_from_hash
    def populate_from_hash( data )
      self.id = data['id'] if data['id']
      self.address = data['address'] if data['address']
      self.port =data['port'] if data['port']
      self.condition = data['condition'] if data['condition']
      @status = data['status'] if data['status']
    end

    VALID_TYPES = %w(PRIMARY SECONDARY)
    # -------------------------------------------------------------------- type=
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
    # --------------------------------------------------------------- condition=
    def condition=( c )
      raise "Invalid condition: #{c}" unless VALID_CONDITIONS.include?( c )
      @condition = c
    end
    # ------------------------------------------------------------------ to_hash
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

class CloudServers::Dns
  require 'nokogiri'
  def initialize( connection )
    @connection = connection
  end

  def create_record( domain, email, records, ttl = 300 )
    d = Domain.new( @connection, nil, domain )
    records.each do |r|
      d.add_record( r )
    end
    d.email_address = email
    d.ttl = 300
    d.create
    return d
  end

  def find_domains( name )
    Domain.find_all_by_name( name, @connection )
  end

  def domains
    Domain.list( @connection )
  end


  class Domain
    attr_reader :name, :id
    attr_writer :email_address
    attr_accessor :ttl

    # --------------------------------------------------------------------- find
    def self.find( connection, id )
      obj = new( connection, id )
      obj.details
      obj
    end
    # --------------------------------------------------------- find_all_by_name
    def self.find_all_by_name( name, connection = nil )
      connection ||= CloudServers::Connection.find_connection!
      domains = []
      connection.dns_paths do |path|
        if path.query
          path.query = [path.query, "name=#{URI.escape(name)}" ].join('&')
        else
          path.query = "name=#{URI.escape(name )}"
        end
        path.path += '/domains'
        r = connection.paginated_request( path )
        r['domains'].each do |domain_hash|
          domains << new( connection, domain_hash['id'], domain_hash['name'] )
        end
      end
      return domains
    end
    # ------------------------------------------------------------- find_by_name
    def self.find_by_name( name, connection = nil )
      domains = find_all_by_name( name, connection )
      if domains.length <= 1
        return domains.first
      else
        raise 'Not exact match.'
      end
    end
    # --------------------------------------------------------------------- list
    def self.list( connection = nil )
      connection ||= CloudServers::Connection.find_connection!
      domains = []
      connection.dns_paths do |path|
        path.path += '/domains'
        r = connection.paginated_request( path )
        r['domains'].each do |domain_hash|
          domains << new( connection, domain_hash['id'], domain_hash['name'] )
        end
      end
      return domains
    end
    # --------------------------------------------------------------------- save
    def save
      if new_record?
        create
      else
        update
      end
    end
    # ------------------------------------------------------------------- create
    def create
      #data = to_json
      #validate_records( records )
      p = @connection.dns_paths.first
      r = @connection.csreq( 'POST', p.host, p.path + "/domains", p.port, p.scheme, { }, to_json_as_array )
      result = @connection.handle_results( r )
      if result.is_a?( CloudServers::AsynchronousJob )
        result =result.wait_for_results( 2 )
      end
      created_domain_hash = result['response']['domains'].find{ |x| x['name'] == name }
      @id = created_domain_hash['id']
    end

    # ------------------------------------------------------------------- update
    def update
      if @records_changed
        raise "API limitations prevent record modification.  Please remove and recreate the domain."
      end
      p = @connection.dns_paths.first
      r = @connection.csreq( 'PUT', p.host, p.path + "/domains/#{id}.json", p.port, p.scheme, {}, to_json )
      @connection.handle_results( r )
    end
      
    # --------------------------------------------------------------- initialize
    def initialize( conn, id = nil, name = nil, details = nil )
      @connection=  conn
      @name = name
      @id = id
      @details = nil
    end

    def self.details_method( *args )
      args.each do |m|
        define_method m do
          details[m.to_s]
        end
      end
    end
    details_method( :emailAddress, :nameservers, :recordsList )


    # ------------------------------------------------------------------ details
    def details
      return {} if id.nil?
      @details ||= begin
        path = @connection.dns_paths.first
        r = @connection.csreq( 'GET', path.host, path.path + "/domains/#{id}", path.port, path.scheme )
        data = @connection.handle_results( r )
        if data.is_a?( CloudServers::AsynchronousJob )
          data = wait_for_results
        end
        @name ||= data['name']
        @id ||= data['id']
        data
      end
    end
    # ------------------------------------------------------------ email_address
    def email_address
      @email_address ||= details['emailAddress']
      return @email_address
    end
    # ------------------------------------------------------------------ records
    def records
      @records ||= begin
        r_val = details['recordsList'] && details['recordsList']['records']
        r_val || []
      end
      return @records
    end

    # ------------------------------------------------------------------ delete!
    def delete!
      raise "Missing required data!" if id.nil?
      p = @connection.dns_paths.first
      r = @connection.csreq( 'DELETE', p.host, p.path + "/domains/#{id}", p.port, p.scheme )
      data = @connection.handle_results( r ) do
        @id = nil
        @details.delete( 'id' ) if @details
        freeze
      end
    end
    # --------------------------------------------------------------- add_record
    def add_record( record )
      @records_changed = true
      records << record
    end
    # --------------------------------------------------------------- add_record
    def add_record!( record )
      p = @connection.dns_paths.first
      r = @connection.csreq( 'POST', p.host, p.path + "/domains/#{id}/records", p.port, p.scheme,
          {}, JSON.generate( { 'records' => [record] } ) )
      result = @connection.handle_results( r ) do
        records << record
      end
      if result.is_a?( CloudServers::AsynchronousJob )
        result = result.wait_for_results
      end
    end
    # ----------------------------------------------------------- remove_record!
    def remove_record!( record_id )
      p = @connection.dns_paths.first
      r = @connection.csreq( 'DELETE', p.host, p.path + "/domains/#{id}/records/#{record_id}", p.port, p.scheme )

      @connection.handle_results( r ) do
        records.reject!{ |x| x['id'] == record_id }
      end
    end
    # ----------------------------------------------------------------- records=
    def records=( records )
      @records_changed = true
      @records = records
    end
    # -------------------------------------------------------------------- name=
    def name=( n )
      if new_record?
        @name = n
      else
        raise "Domain name cannot be changed, please delete and recreate"
      end
    end
    # -------------------------------------------------------------- new_record?
    def new_record?
      details['id'].nil?
    end
    # --------------------------------------------------------- to_json_as_array
    def to_json_as_array
      adjusted_records = records.map do |record|
        %w( id updated created ).each do |bad_key|
          record.delete( bad_key )
        end
        if record['ttl'].nil?
          record['ttl'] = @ttl || 300
        end
        record
      end
      adjusted_records = adjusted_records.find_all do |record|
        record['type'] != 'NS'
      end
      data = {"emailAddress" => email_address, 'ttl' => @ttl || 300, "recordsList" => { "records" => adjusted_records } }
      if new_record?
        data['name'] = name
      else
        data['id'] = id
      end
      data = { 'domains' => [data] }
      return JSON.generate( data  )
    end
    # --------------------------------------------------------------- build_json
    def to_json
      adjusted_records = records.map do |record|
        %w( id updated created ).each do |bad_key|
          record.delete( bad_key )
        end
        record
      end
      adjusted_records = adjusted_records.find_all do |record|
        record['type'] != 'NS'
      end
      data = {"emailAddress" => email_address, "recordsList" => { "records" => adjusted_records } }
      if new_record?
        data['name'] = name
      else
        data['id'] = id
      end
      return JSON.generate( data  )
    end

  end #end domain class

  def parse_create_results( json )
    parse_domains_json( json )
  end

################################################################################
private
################################################################################

  def parse_domains_json( json )
    if json.is_a?( String )
      result = JSON.parse( json ) 
    else
      result = json
    end
    result = result['response'] if result['response']
    r_val = []
    if result['domains']
      result['domains'].each do |d|
        r_val << Domain.new( @connection, d['id'].to_i, d['name'] )
      end
    end
    return r_val
  end

  def validate_records( records )
    records.each do |r|
      unless r.key?( 'name' ) || r.key?( :name )
        raise "Missing name field in #{r.inspect}"
      end
    end
  end

  def build_xml( domain, records, email, ttl )
    xml = Nokogiri::XML::Builder.new do |doc|
      doc.domains( :xmlns => "http://docs.rackspacecloud.com/dns/api/v1.0" ) {
          doc.domain( :name => domain, :emailAddress => email ) {
            doc.recordsList {
              records.each { |r| doc.record( r ) }
            }
         }
      }
    end
    xml.to_xml
  end

  def build_json( domain, records, email, ttl = 300 )
    data = { :domains => { :domain => [{ :name => domain, :records => records, :emailAddress => email }]}}
    JSON.generate( data  )
  end

end

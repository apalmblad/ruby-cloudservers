class CloudServers::Dns
  require 'nokogiri'
  API_SERVER = 'dns.api.rackspacecloud.com'
  def initialize( connection )
    @connection = connection
  end

  def create_record( domain, email, records, ttl = 300 )
    data = build_xml( domain, records, email, ttl )
    validate_records( records )
    r = @connection.csreq( 'POST', API_SERVER, "#{@connection.svrmgmtpath}/domains.json", @connection.svrmgmtport, @connection.svrmgmtscheme, { 'content-type' => 'application/xml' }, data )
    @connection.handle_results( r )
  end


  def find_domains( name )
    r = @connection.csreq( 'GET', API_SERVER, "#{@connection.svrmgmtpath}/domains.json?name=#{URI.encode(name)}", @connection.svrmgmtport, @connection.svrmgmtscheme )
    result = @connection.handle_results( r )
    if result.is_a?( CloudServers::AsynchronousJob )
      result = result.wait_for_results
    end
    return parse_domains_json( result )
  end

  def domains
    r = @connection.csreq( 'GET', API_SERVER, "#{@connection.svrmgmtpath}/domains.json", @connection.svrmgmtport, @connection.svrmgmtscheme )
    result = @connection.handle_results( r )
    if result.is_a?( CloudServers::AsynchronousJob )
      result = wait_for_results
    end
    return parse_domains_json( result )
  end


  class Domain
    attr_reader :name, :id
    attr_writer :email_address

    # --------------------------------------------------------------------- find
    def self.find( connection, id )
      obj = new( connection, id )
      obj.details
      obj
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
      r = @connection.csreq( 'POST', API_SERVER, "#{@connection.svrmgmtpath}/domains.json", @connection.svrmgmtport, @connection.svrmgmtscheme, { 'content-type' => 'application/json' }, to_json_as_array )
      @connection.handle_results( r )
    end

    # ------------------------------------------------------------------- update
    def update
      if @records_changed
        raise "API limitations prevent record modification.  Please remove and recreate the domain."
      end
      r = @connection.csreq( 'PUT', API_SERVER, "#{@connection.svrmgmtpath}/domains/#{id}.json", @connection.svrmgmtport, @connection.svrmgmtscheme, { 'content-type' => 'application/json' }, to_json )
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
      @details ||= begin
        r = @connection.csreq( 'GET', API_SERVER, "#{@connection.svrmgmtpath}/domains/#{id}.json", @connection.svrmgmtport, @connection.svrmgmtscheme )
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
      r = @connection.csreq( 'DELETE', API_SERVER, "#{@connection.svrmgmtpath}/domains/#{id}.json", @connection.svrmgmtport, @connection.svrmgmtscheme )
      data = @connection.handle_results( r ) do
        details.delete( 'id' )
        @id = nil
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
      r = @connection.csreq( 'POST', API_SERVER, "#{@connection.svrmgmtpath}/domains/#{id}/records", @connection.svrmgmtport, @connection.svrmgmtscheme,
          { 'content-type' => 'application/json' }, JSON.generate( { 'records' => [record] } ) )
      @connection.handle_results( r ) do
        records << record
      end
    end
    # ----------------------------------------------------------- remove_record!
    def remove_record!( record_id )
      r = @connection.csreq( 'DELETE', API_SERVER, "#{@connection.svrmgmtpath}/domains/#{id}/records/#{record_id}", @connection.svrmgmtport, @connection.svrmgmtscheme, { 'content-type' => 'application/json' } )

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
    def to_json_as_array
      adjusted_records = records.map do |record|
        %w( id updated created ).each do |bad_key|
          record.delete( bad_key )
        end
        if record['ttl'].nil?
          record['ttl'] = 300
        end
        record
      end
      adjusted_records = adjusted_records.find_all do |record|
        record['type'] != 'NS'
      end
      data = {"emailAddress" => email_address, 'ttl' => 300, "recordsList" => { "records" => adjusted_records } }
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

  def build_json( domain, records, email, ttl )
    data = { :domains => { :domain => [{ :name => domain, :records => records, :emailAddress => email }]}}
    JSON.generate( data  )
  end

end

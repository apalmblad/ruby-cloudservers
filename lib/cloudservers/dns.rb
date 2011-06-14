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
    if r.code.to_i == 202
      result = JSON.parse( r.body )
      CloudServers::AsynchronousJob.new( @connection, result['asyncResponse']['jobId'], result['asyncResponse']['callbackUrl'] )
    else
      CloudServers::Exception.raise_exception(r)
    end
  end

  def find_domains( name )
    r = @connection.csreq( 'GET', API_SERVER, "#{@connection.svrmgmtpath}/domains.json?name=#{URI.encode(name)}", @connection.svrmgmtport, @connection.svrmgmtscheme )
    if r.code.match( /^20.$/ )
      parse_domains_json( r.body )
    elsif r.code.to_i == 404
      return []
    else
      raise CloudServers::Exception.raise_exception(r) 
    end
  end

  def domains
    r = @connection.csreq( 'GET', API_SERVER, "#{@connection.svrmgmtpath}/domains.json", @connection.svrmgmtport, @connection.svrmgmtscheme )
    raise CloudServers::Exception.raise_exception(r) unless r.code.match( /^20.$/ )
    self.class.arse_domains_json( r.body )
  end


  class Domain
    attr_reader :name, :id
    
    def initialize( conn, id, name = nil, details = nil )
      @connection=  conn
      @name= name
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
    details_method( :emailAddress, :nameservers, :records )


    def details
      @details ||= begin
        r = @connection.csreq( 'GET', API_SERVER, "#{@connection.svrmgmtpath}/domains/#{id}.json", @connection.svrmgmtport, @connection.svrmgmtscheme )
        if r.code =~ /^20.$/
          data =  JSON.parse( r.body )
          @name ||= data['Domain']['name']
          @id ||= data['Domain']['id']
          data['Domain']
        else
          raise CloudServers::Exception.raise_exception(r)
        end
      end
    end

    def delete!
      r = @connection.csreq( 'DELETE', API_SERVER, "#{@connection.svrmgmtpath}/domains/#{id}.json", @connection.svrmgmtport, @connection.svrmgmtscheme )
      if r.code.match( /^20.$/ )
        freeze
        return CloudServers::AsynchronousJob.from_json( @connection, r.body )
      else
        CloudServers::Exception.raise_exception(r)
      end
    end

  end

  def parse_create_results( json )
    parse_domains_json( json )
  end

################################################################################
private
################################################################################

  def parse_domains_json( json )
    result = JSON.parse( json )
    r_val = []
    if result['domains']
      result['domains']['domain'].each do |d|
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
            doc.records {
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

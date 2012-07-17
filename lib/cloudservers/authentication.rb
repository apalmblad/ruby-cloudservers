module CloudServers
  class Authentication

    # Performs an authentication to the Rackspace Cloud authorization servers.  Opens a new HTTP connection to the API server,
    # sends the credentials, and looks for a successful authentication.  If it succeeds, it sets the svrmgmthost,
    # svrmgtpath, svrmgmtport, svrmgmtscheme, authtoken, and authok variables on the connection.  If it fails, it raises
    # an exception.
    #
    # Should probably never be called directly.
    def initialize(connection)
      path = '/v1.1/auth'
      begin
        server = Net::HTTP::Proxy(connection.proxy_host, connection.proxy_port).new(connection.auth_host,connection.auth_port)
        if connection.auth_scheme == "https"
          server.use_ssl = true
          server.verify_mode = OpenSSL::SSL::VERIFY_NONE
        end
        server.start
      rescue
        raise CloudServers::Exception::Connection, "Unable to connect to #{server}"
      end

      request = Net::HTTP::Post.new( path, { 'Content-Type' => 'application/json' } )
      request.body = {"credentials" => { "username" => connection.auth_user, "key" => connection.auth_key }}.to_json

      response = server.request( request )
                                   
      if (response.code =~ /^20./)
        body = JSON.parse( response.body )
        token = body['auth']['token']
        connection.authtoken = token['id']
        connection.service_catalog = body['auth']['serviceCatalog']
        connection.authok = true
      else
        connection.authtoken = false
        raise CloudServers::Exception::Authentication.new( "Authentication failed!", response.code, response.body )
      end
      server.finish
    end
  end
end

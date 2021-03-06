require_relative '../asf.rb'
require 'rack'
require 'etc'

module ASF
  module Auth
    DIRECTORS = {
      'rbowen'      => 'rb',
      'curcuru'     => 'sc',
      'bdelacretaz' => 'bd',
      'jim'         => 'jj',
      'mattmann'    => 'cm',
      'ke4qqq'      => 'dn',
      'brett'       => 'bp',
      'rubys'       => 'sr',
      'gstein'      => 'gs'
    }

    # decode HTTP authorization, when present
    def self.decode(env)
      class << env; attr_accessor :user, :password; end

      if env['HTTP_AUTHORIZATION']
        require 'base64'
        env.user, env.password = Base64.decode64(env['HTTP_AUTHORIZATION'][
          /^Basic ([A-Za-z0-9+\/=]+)$/,1]).split(':',2)
      else
        env.user = env['REMOTE_USER'] || ENV['USER'] || Etc.getpwuid.name
      end

      env['REMOTE_USER'] ||= env.user

      ASF::Person.new(env.user)
    end

    # Simply 'use' the following class in config.ru to limit access
    # to the application to ASF committers
    class Committers < Rack::Auth::Basic
      def initialize(app)
        super(app, "ASF Committers", &proc {})
      end

      def call(env)
        authorized = ( ENV['RACK_ENV'] == 'test' )

        authorized ||= ASF::Auth.decode(env).asf_committer?

        if authorized
          @app.call(env)
        else
          unauthorized
        end
      end
    end

    # Simply 'use' the following class in config.ru to limit access
    # to the application to ASF members and officers and the accounting group.
    class MembersAndOfficers < Rack::Auth::Basic
      def initialize(app)
        super(app, "ASF Members and Officers", &proc {})
      end

      def call(env)
        authorized = ( ENV['RACK_ENV'] == 'test' )

        person = ASF::Auth.decode(env)

        authorized ||= DIRECTORS[env.user]
        authorized ||= person.asf_member?
        authorized ||= ASF.pmc_chairs.include? person

        if not authorized
          accounting = ASF::Authorization.new('pit').
            find {|group, list| group=='accounting'}
          authorized = (accounting and accounting.last.include? env.user)
        end

        if authorized
          @app.call(env)
        else
          unauthorized
        end
      end
    end
  end

  # Apache httpd on whimsy-vm is behind a proxy that converts https
  # requests into http requests.  Update the environment variables to
  # match.
  class HTTPS_workarounds
    def initialize(app)
      @app = app
    end

    def call(env)
      if env['HTTPS'] == 'on'
        env['SCRIPT_URI'].sub!(/^http:/, 'https:')
        env['SERVER_PORT'] = '443'

        # for reasons I don't understand, Passenger on whimsy doesn't
        # forward root directory requests directly, so as a workaround
        # these requests are rewritten and the following code maps
        # the requests back:
        if env['PATH_INFO'] == '/index.html'
          env['PATH_INFO'] = '/'
          env['SCRIPT_URI'] += '/'
        end
      end
      return  @app.call(env)
    end
  end

end

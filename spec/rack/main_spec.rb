require_relative '../helpers/main/expectations'

RSpec.describe(Main, type: :rack_test) {
  include RSpec::MainExpectations

  context('get /') {
    it('displays logged out page when there is no email cookie') {
      expect_slim(:index, email: false, req: an_instance_of(Tony::Request))
      get '/'
      expect(last_response.ok?).to(be(true))
    }

    it('displays logged in page when there is an email cookie') {
      set_cookie(:email, 'test@example.com')
      get '/'
      expect_logged_in_index_page('test@example.com')
    }

    it('does not delete the email cookie') {
      set_cookie(:email, 'nomnomnom')
      get '/'
      expect(get_cookie(:email)).to(eq('nomnomnom'))
    }
  }

  context('in faux production') {
    def get_path(path)
      # rubocop:disable Style/StringHashKeys
      get(path, {}, { 'HTTPS' => 'on' })
      # rubocop:enable Style/StringHashKeys
    end

    before(:all) {
      ENV['APP_ENV'] = 'production'
      ENV['RACK_ENV'] = 'production'
      Capybara.app = Rack::Builder.parse_file('config.ru').first
    }

    before(:each) {
      ENV['APP_ENV'] = 'production'
      ENV['RACK_ENV'] = 'production'
    }

    it('displays logged out page when there is no email cookie') {
      get_path('/')
      expect_logged_out_index_page
    }

    it('displays logged in page when there is an email cookie') {
      set_cookie(:email, 'test@example.com')
      get_path('/')
      expect_logged_in_index_page('test@example.com')
    }

    it('does not display raised error messages in production') {
      get_path('/throw_error')
      expect_production_error_page
    }

    after(:all) {
      ENV['APP_ENV'] = 'test'
      ENV['RACK_ENV'] = 'test'
      Capybara.app = Rack::Builder.parse_file('config.ru').first
    }
  }

  context('get /logout') {
    it('deletes the email cookie') {
      set_cookie(:email, 'nomnomnom')
      get '/logout'
      expect(get_cookie(:email)).to(be_nil)
    }

    it('redirects after logging out') {
      get '/logout?r=/somewhere_else'
      expect(last_response.redirect?).to(be(true))
      expect(last_response.location).to(eq('/somewhere_else'))
    }
  }

  context('get /auth/google') {
    before(:each) {
      @login_info = Tony::Auth::LoginInfo.new(email: 'jubi@github.com',
                                              state: { r: '/onward' })
    }

    it('sets the email address') {
      set_cookie(:email, 'nomnomnom')
      # rubocop:disable Style/StringHashKeys
      get '/auth/google', {}, { 'login_info' => @login_info }
      # rubocop:enable Style/StringHashKeys
      expect(get_cookie(:email)).to(eq('jubi@github.com'))
    }

    it('redirects to :r in state') {
      # rubocop:disable Style/StringHashKeys
      get '/auth/google', {}, { 'login_info' => @login_info }
      # rubocop:enable Style/StringHashKeys
      expect(last_response.redirect?).to(be(true))
      expect(last_response.location).to(eq('/onward'))
    }
  }

  it('returns not found to unknown urls') {
    get '/not_a_url'
    expect_not_found_page
  }
}

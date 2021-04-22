RSpec.describe('/') {
  include_context(:rack_test)

  context('/') {
    it('responds to / with OK status') {
      get '/'
      expect(last_response.ok?).to(be(true))
      expect(last_response.body).to(have_no_link(href: '/logout'))
    }

    it('does not delete the email cookie') {
      set_cookie('email=nomnomnom')
      get '/'
      expect(rack_mock_session.cookie_jar['email']).to(eq('nomnomnom'))
    }

    it('welcomes user when they have email cookie') {
      self.email_cookie = 'test@example.com'
      get '/'
      expect(last_response.body).to(include('test@example.com'))
      expect(last_response.body).to(have_link(href: '/logout'))
    }
  }

  context('/logout') {
    it('deletes the email cookie') {
      set_cookie('email=nomnomnom')
      get '/logout'
      expect(rack_mock_session.cookie_jar['email']).to(eq(''))
    }
  }
}

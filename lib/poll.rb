require_relative 'base'
require_relative 'models/choice'
require_relative 'models/poll'
require_relative 'utils/email'

class Poll < Base
  include Helpers::Cookie
  include Helpers::Guard

  def initialize
    super(Tony::Slim.new(views: 'views',
                         layout: 'views/layout',
                         options: {
                           include_dirs: [
                             File.join(Dir.pwd, 'views/poll/partials')
                           ]
                         }))

    get('/poll/create', ->(req, resp) {
      require_email(req, resp)
      resp.write(@slim.render('poll/create'))
    })

    post('/poll/create', ->(req, resp) {
      require_email(req, resp)
      begin
        poll = Models::Poll.create(**req.params.to_h.symbolize_keys)
      rescue Models::ArgumentError => error
        resp.status = 406
        resp.write(error.message)
      else
        resp.redirect(poll.url)
      end
    })

    get(%r{^/poll/view/(?<poll_id>.+)$}, ->(req, resp) {
      poll = require_poll(req, resp)

      if poll.finished?
        breakdown, = poll.breakdown
        resp.write(@slim.render('poll/finished', poll: poll,
                                                 breakdown: breakdown))
        return
      end

      if req.params.key?(:responder)
        responder = poll.responder(salt: req.params.fetch(:responder))
        unless responder
          resp.write(@slim.render('email/get', poll: poll, req: req))
          return
        end

        resp.set_cookie(:email, responder.email)
        resp.redirect(poll.url)
        return
      end

      email = fetch_email(req)
      unless email
        resp.write(@slim.render('email/get', poll: poll, req: req))
        return
      end

      responder = poll.responder(email: email)
      unless responder
        resp.write(@slim.render('email/get', poll: poll, req: req))
        return
      end

      timezone = req.cookies.fetch('tz', 'America/Los_Angeles')
      template = responder.responses.empty? ? :view : :responded
      resp.write(@slim.render("poll/#{template}", poll: poll,
                                                  responder: responder,
                                                  timezone: timezone))
    })

    post('/poll/send', ->(req, resp) {
      poll = require_poll(req, resp)

      unless req.params.key?(:email)
        resp.status = 400
        resp.write('No responder provided')
        return
      end

      responder = poll.responder(email: req.params.fetch(:email))
      unless responder
        resp.status = 404
        resp.write(@slim.render('email/responder_not_found'))
        return
      end

      begin
        Utils::Email.email(poll, responder)
      rescue Utils::ArgumentError => error
        resp.status = 405
        resp.write(error.message)
        return
      end

      resp.write(@slim.render('email/sent'))
    })

    post('/poll/respond', ->(req, resp) {
      poll = require_poll(req, resp)
      email = require_email(req, resp)

      unless req.params.key?(:responder)
        resp.status = 400
        resp.write('No responder provided')
        return
      end

      responder = poll.responder(salt: req.params.fetch(:responder))
      unless responder
        resp.status = 404
        resp.write('Responder not found')
        return
      end

      if responder.email != email
        resp.status = 405
        resp.write('Logged in user is not the responder in the form')
        return
      end

      begin
        case poll.type
        when :borda_single, :borda_split
          save_borda_poll(req, resp, poll, responder)
        when :choose_one
          save_choose_one_poll(req, resp, responder)
        end
      rescue Sequel::UniqueConstraintViolation
        resp.status = 409
        resp.write('Duplicate response or choice found')
      rescue Sequel::HookFailed => error
        resp.status = 405
        resp.write(error.message)
      else
        resp.status = 201
        resp.write('Poll created')
      end
    })
  end

  private

  def save_choose_one_poll(req, resp, responder)
    unless req.params.key?(:choice)
      resp.status = 400
      resp.write('No choice provided')
      throw(:response)
    end
    choice_id = req.params.fetch(:choice)
    responder.add_response(choice_id: choice_id)
  end

  def save_borda_poll(req, resp, poll, responder)
    unless req.params.key?(:responses)
      resp.status = 400
      resp.write('No responses provided')
      throw(:response)
    end
    responses = req.params.fetch(:responses)

    if poll.type == :borda_split && !req.params.key?(:bottom_responses)
      resp.status = 400
      resp.write('No bottom response array provided for a borda_split poll')
      throw(:response)
    end

    bottom_responses = req.params.fetch(:bottom_responses, [])
    unless responses.length + bottom_responses.length == poll.choices.length
      resp.status = 406
      resp.write('Response set does not match number of choices')
      throw(:response)
    end

    responses.each_with_index { |choice_id, rank|
      score = poll.choices.length - rank
      score -= 1 if poll.type == :borda_single
      responder.add_response(choice_id: choice_id, score: score)
    }
  end
end

require 'core'
require 'linguistics'
require 'sequel'
require 'sinatra'
require 'sinatra/content_for'
require 'sinatra/static'
require 'slim'
require 'slim/include'

Linguistics.use(:en)
Slim::Engine.set_options(
    tabsize: 2,
    include_dirs: ["#{Dir.pwd}/views/partials"],
    pretty: ENV.fetch('APP_ENV') == 'development')

DB = Sequel.sqlite('.data/db.sqlite')
Sequel.extension(:migration)
Sequel::Migrator.check_current(DB, 'db/migrations')

require_relative 'models/poll'
require_relative 'models/responder'
require_relative 'utils/email'

class JubiVote < Sinatra::Base
  helpers Sinatra::ContentFor
  register Sinatra::Static

  set(public_folder: 'public')
  set(views: 'views')

  get('/') {
    slim :index
  }

  not_found {
    status 404
    slim :not_found
  }

  #####################################
  # POLL
  #####################################
  get('/poll/:poll_id') {
    poll = Poll[params.fetch(:poll_id)]
    return poll_not_found unless poll

    unless params.key?(:responder)
      return slim_email(:get, locals: { poll: poll })
    end

    responder = poll.responder(salt: params.fetch(:responder))
    return slim_email(:get, locals: { poll: poll }) unless responder

    template = responder.responses.empty? ? :poll : :created
    slim_poll(template, locals: { poll: poll, responder: responder })
  }

  post('/send_email') {
    poll = Poll[params.fetch(:poll_id)]
    return poll_not_found unless poll

    responder = poll.responder(email: params.fetch(:email))
    return email_not_found unless responder

    Email.send_email(poll, responder)
    return slim_email(:sent)
  }

  post('/poll_response') {
    params = JSON.parse(request.body.read).symbolize_keys
    poll = Poll[params.fetch(:poll_id)]
    return status(404) unless poll

    responder = poll.responder(salt: params.fetch(:responder))
    return status(404) unless responder

    begin
      params.fetch(:responses).each_with_index { |choice_id, rank|
        responder.add_response(choice_id: choice_id, rank: rank)
      }
    rescue Sequel::UniqueConstraintViolation
      return status(409)
    end

    return status(201)
  }

  #####################################
  # ADMIN
  #####################################
  get('/admin') {
    slim_admin :admin
  }

  get('/admin/create_poll') {
    slim_admin :create_poll
  }

  post('/admin/new_poll') {
    poll = Poll.create_poll(
        title: params.fetch(:title),
        expiration: params.fetch(:expiration),
        choices: params.fetch(:choices).strip.split(/\s*,\s*/),
        responders: params.fetch(:responders).strip.split(/\s*,\s*/))
    redirect "/admin/poll/#{poll.id}"
  }

  get('/admin/poll/:poll_id') {
    poll = Poll[params.fetch(:poll_id)]
    return poll_not_found unless poll

    slim_admin :poll, locals: { poll: poll }
  }

  #####################################
  # PRIVATE
  #####################################

  private

  def email_not_found
    status(404)
    slim_email(:not_found)
  end

  def poll_not_found
    status(404)
    slim_poll(:not_found)
  end

  def slim_admin(template, **options)
    slim(template, **options.merge(views: 'views/admin', layout: :'../layout'))
  end

  def slim_email(template, **options)
    slim(template, **options.merge(views: 'views/email', layout: :'../layout'))
  end

  def slim_poll(template, **options)
    slim(template, **options.merge(views: 'views/poll', layout: :'../layout'))
  end
end

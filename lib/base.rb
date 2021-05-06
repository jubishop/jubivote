require 'tony'

require_relative 'helpers/cookie'
require_relative 'helpers/guard'

class Base < Tony::App
  include Helpers::Cookie
  include Helpers::Guard

  def initialize
    super(secret: ENV.fetch('JUBIVOTE_COOKIE_SECRET'))
    @slim = Tony::Slim.new(views: 'views', layout: 'views/layout')

    not_found(->(_, resp) {
      resp.write(slim.render(:not_found))
    })
  end

  private

  attr_reader :slim
end

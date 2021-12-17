require_relative '../../lib/models/poll'

module RSpec
  module Models
    def create(title: 'title',
               question: 'question',
               expiration: Time.now.to_i + 62,
               choices: 'one, two, three',
               responders: 'a@a',
               type: nil)
      return ::Models::Poll.create(title: title,
                                   question: question,
                                   expiration: expiration,
                                   choices: choices,
                                   responders: responders,
                                   type: type)
    end
  end
end

module Models
  class Poll
    include Test::Env

    def mock_response
      test_only!
      responder = responder(email: 'a@a')
      responses = choices.map(&:id)

      case type
      when :borda_single, :borda_split
        responses.each_with_index { |choice_id, rank|
          score = responses.length - rank
          score -= 1 if type == :borda_single

          responder.add_response(choice_id: choice_id, score: score)
        }
      when :choose_one
        responder.add_response(choice_id: choices.first.id)
      end

      return responses
    end
  end
end

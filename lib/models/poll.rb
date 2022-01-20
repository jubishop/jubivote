# Table: polls
# Columns:
#  id         | bigint                      | PRIMARY KEY GENERATED BY DEFAULT AS IDENTITY
#  email      | text                        | NOT NULL
#  group_id   | bigint                      | NOT NULL
#  created_at | timestamp without time zone | NOT NULL
#  updated_at | timestamp without time zone | NOT NULL
#  title      | text                        | NOT NULL
#  question   | text                        | NOT NULL
#  expiration | timestamp without time zone | NOT NULL
#  type       | poll_type                   | NOT NULL
# Indexes:
#  polls_pkey | PRIMARY KEY btree (id)
# Check constraints:
#  question_not_empty | (char_length(question) >= 1)
#  title_not_empty    | (char_length(title) >= 1)
# Foreign key constraints:
#  polls_email_fkey    | (email) REFERENCES users(email)
#  polls_group_id_fkey | (group_id) REFERENCES groups(id) ON DELETE CASCADE
# Referenced By:
#  choices | choices_poll_id_fkey | (poll_id) REFERENCES polls(id) ON DELETE CASCADE

require 'rstruct'
require 'sequel'

require_relative '../helpers/email'
require_relative 'helpers/poll_results'
require_relative 'choice'
require_relative 'group'
require_relative 'response'
require_relative 'user'

BreakdownResult = KVStruct.new(:member, :score)

module Models
  class Poll < Sequel::Model
    include ::Helpers::Email

    many_to_one :creator, class: 'Models::User', key: :email
    many_to_one :group
    one_to_many :choices, remover: ->(choice) { choice.destroy }, clearer: nil
    many_to_many :responses, join_table: :choices,
                             right_key: :id,
                             right_primary_key: :choice_id,
                             adder: nil,
                             remover: nil,
                             clearer: nil
    plugin :timestamps, update_on_create: true
    plugin :hash_id, salt: ENV.fetch('POLL_ID_SALT').freeze

    def before_validation
      cancel_action('Poll has no group') unless group_id
      if (message = invalid_email(email: email, name: 'Poll'))
        cancel_action(message)
      end
      unless member(email: creator.email)
        cancel_action("Creator #{email} is not a member of #{group.name}")
      end
      cancel_action('Expiration value is invalid') unless expiration.is_a?(Time)
      super
    end

    def before_create
      cancel_action('Poll is created expired') if finished?
      super
    end

    def members
      return Member.where(group_id: group_id).all
    end

    def member(email:)
      return Member.where(group_id: group_id, email: email).first
    end

    def creating_member
      return member(email: creator.email)
    end

    def choice(text:)
      return choices_dataset.where(text: text).first
    end

    def finished?
      return expiration < Time.now
    end

    def scores
      assert_finished
      assert_type(:borda_single, :borda_split)

      point_results = Helpers::PollResults.new(responses)
      scores_results = Helpers::PollResults.new(responses) { |response|
        response.data[:score]
      }
      return scores_results.values.sort_by! { |result|
        [-result.to_i, -point_results[result.choice].to_i]
      }
    end

    def counts
      assert_finished
      assert_type(:borda_split, :choose_one)

      point_results = Helpers::PollResults.new(responses)
      case type
      when :choose_one
        return point_results.to_a
      when :borda_split
        scores_results = Helpers::PollResults.new(responses) { |response|
          response.data[:score]
        }
        return point_results.values.sort_by! { |result|
          [-result.to_i, -scores_results[result.choice].to_i]
        }
      end
    end

    def breakdown
      assert_finished
      assert_type(:choose_one, :borda_single, :borda_split)

      results = Hash.new { |hash, key| hash[key] = [] }
      unresponded = []
      members.each { |member|
        if member.responses.empty?
          unresponded.push(member)
        else
          member.responses.each { |response|
            results[response.choice].push(
                BreakdownResult.new(member: member,
                                    score: response.data[:score]))
          }
        end
      }
      return results, unresponded
    end

    def type
      return super.to_sym
    end

    def url
      return "/poll/view/#{hashid}"
    end

    def to_s
      return title
    end

    private

    def assert_finished
      return if finished?

      raise SecurityError, "#{title} is not finished"
    end

    def assert_type(*types)
      return if types.include?(type)

      raise TypeError, "#{title} has type: #{type} but must be one of " \
                       "#{types.sentence('or')} for this method"
    end
  end
end

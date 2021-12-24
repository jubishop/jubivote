require 'rstruct'
require 'sequel'

require_relative 'choice'
require_relative 'helpers/poll_results'

BreakdownResult = KVStruct.new(:member, :score)

module Models
  class Poll < Sequel::Model
    many_to_one :creator, class: 'Models::User', key: :email
    many_to_one :group
    one_to_many :choices
    many_to_many :responses, join_table: :choices,
                             right_key: :id,
                             right_primary_key: :choice_id
    plugin :timestamps, update_on_create: true

    def before_validation
      unless member(email: creator.email)
        cancel_action("Creator: #{email} is not a group member")
      end
      super
    end

    def members
      return Member.where(group_id: group_id).all
    end

    def member(email:)
      return Member.find(group_id: group_id, email: email)
    end

    def creating_member
      return member(email: creator.email)
    end

    def choice(text:)
      return Choice.find(poll_id: id, text: text)
    end

    def type
      return super.to_sym
    end

    def shuffled_choices
      return choices.shuffle!
    end

    def finished?
      return Time.at(expiration) < Time.now
    end

    def scores
      assert_type(:borda_single, :borda_split)

      return Helpers::PollResults.new(responses, &:score).to_a
    end

    def counts
      assert_type(:borda_split, :choose_one)

      point_results = Helpers::PollResults.new(responses)
      case type
      when :choose_one
        return point_results.to_a
      when :borda_split
        scores_results = Helpers::PollResults.new(responses, &:score)
        return point_results.values.sort_by! { |result|
          [-result.count, -scores_results[result.choice].score]
        }
      end
    end

    def breakdown
      assert_type(:choose_one, :borda_single, :borda_split)

      results = Hash.new { |hash, key| hash[key] = [] }
      unresponded = []
      members.each { |member|
        if member.responses.empty?
          unresponded.push(member)
        else
          member.responses.each { |response|
            results[response.choice].push(BreakdownResult.new(
                                              member: member,
                                              score: response.score))
          }
        end
      }
      return results, unresponded
    end

    def url
      return "/poll/view/#{id}"
    end

    def to_s
      return title
    end

    private

    def assert_type(*types)
      return if types.include?(type)

      raise TypeError, "#{title} has type: #{type} but must be one of " \
                       "#{types.sentence('or')} for this method"
    end
  end
end

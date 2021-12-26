# Table: responses
# Columns:
#  id        | bigint  | PRIMARY KEY GENERATED BY DEFAULT AS IDENTITY
#  choice_id | bigint  | NOT NULL
#  member_id | bigint  | NOT NULL
#  score     | integer |
# Indexes:
#  responses_pkey  | PRIMARY KEY btree (id)
#  response_unique | UNIQUE btree (member_id, choice_id)
# Foreign key constraints:
#  responses_choice_id_fkey | (choice_id) REFERENCES choices(id) ON DELETE CASCADE
#  responses_member_id_fkey | (member_id) REFERENCES members(id) ON DELETE CASCADE

require 'sequel'

require_relative 'choice'
require_relative 'member'

module Models
  class Response < Sequel::Model
    many_to_one :choice
    many_to_one :member
    one_through_one :poll, join_table: :choices,
                           left_key: :id,
                           left_primary_key: :choice_id

    def before_validation
      cancel_action('Response has no choice') unless choice
      cancel_action('Response has no poll') unless poll
      cancel_action('Response modified in expired poll') if poll.finished?
      super
    end

    def before_destroy
      cancel_action('Response removed from expired poll') if poll.finished?
      super
    end

    def to_s
      choice.to_s
    end
  end
end

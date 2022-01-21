require 'duration'
require 'tzinfo'

require_relative 'shared_examples/entity_flows'

RSpec.describe(Poll, type: :feature) {
  let(:goldens) { Tony::Test::Goldens::Page.new(page, 'spec/goldens/poll') }

  let(:entity) { create_poll }
  it_has_behavior('entity flows')

  before(:each) {
    # Need a fixed moment in time for consistent goldens.
    freeze_time(Time.new(1982, 6, 6, 11, 30, 0,
                         TZInfo::Timezone.get('America/New_York')))
  }

  context(:create) {
    let(:group) { |context|
      create_group(email: context.full_description.to_email('poll.com'),
                   name: context.description)
    }

    it('shows poll form ready to be filled in') {
      set_cookie(:email, group.email)
      go('/poll/create')

      expect(page).to(have_field('expiration', with: (Time.now + 7.days).form))
      goldens.verify('create_empty')
    }

    it('creates a poll with complex :choices creation') {
      # Fill in basic data for a poll.
      set_cookie(:email, group.email)
      go('/poll/create')
      fill_in('title', with: 'this is my title')
      fill_in('question', with: 'what is life')
      fill_in('expiration', with: Time.now + 5.days)
      select('Borda Split', from: 'type')

      # Sometimes click Add button, sometimes press enter on input field, in
      # either case the new input field gets focus.
      click_button('Add Choice')
      %w[zero one two three four five six].each_with_index { |choice, index|
        input_field = all('input.text').last
        expect(input_field).to(have_focus)
        if index.even?
          input_field.fill_in(with: choice)
          click_button('Add Choice')
        else
          input_field.fill_in(with: "#{choice}\n")
        end
      }

      # Delete last empty field and "two".
      all('li.listable div').last.click
      all('li.listable div')[2].click

      # Ensure clicking Add button and pressing enter do nothing when there's
      # already an empty field, and focuses the empty field.
      empty_field = all('input.text')[1]
      empty_field.fill_in(with: '')
      click_button('Add Choice')
      expect(empty_field).to(have_focus)
      all('input.text')[4].native.send_keys(:enter)
      expect(empty_field).to(have_focus)

      # Replace the now empty field ("one") with "seven".
      empty_field.fill_in(with: 'seven')

      # Click on title to remove focus from any form input.
      find('h1').click
      goldens.verify('create_filled_in')

      # Confirm redirect to viewing poll after creation.
      expect_slim(
          'poll/view',
          poll: an_instance_of(Models::Poll),
          member: group.creating_member,
          timezone: an_instance_of(TZInfo::DataTimezone))
      click_button('Create Poll')

      # Ensure actual changes made in DB.
      expect(group.polls.map(&:title)).to(include('this is my title'))
    }

    it('displays a modal and redirects you when you have no group') {
      set_cookie(:email, email)
      go('/poll/create')
      expect(find('#group-modal')).to(
          have_link('Create Group', href: '/group/create'))
      expect(page).to(have_modal)
      goldens.verify('create_no_group_modal')
    }

    it('uses group_id to select a specific group option') {
      user = create_user
      set_cookie(:email, user.email)
      5.times { user.add_group }
      group = user.add_group(name: 'special group')
      go("/poll/create?group_id=#{group.id}")
      goldens.verify('create_specific_group')
    }
  }

  context(:view) {
    let(:poll) {
      create_poll(email: "#{type}@view.com",
                  title: "#{type}_title",
                  question: "#{type}_question",
                  type: type)
    }
    let(:member) { poll.creating_member }

    def expect_responded_slim
      expect_slim(
          'poll/responded',
          poll: poll,
          member: member,
          timezone: an_instance_of(TZInfo::DataTimezone))
    end

    def expect_expiration_text
      expect(page).to(have_content('This poll ends on Jun 06 1982, ' \
                                   'at 11:25 PM +07 (55 minutes from now).'))
    end

    before(:each) {
      allow_any_instance_of(Array).to(receive(:shuffle, &:to_a))
      set_cookie(:email, poll.email)
      %w[zero one two three four five six].each { |choice|
        poll.add_choice(text: choice)
      }
    }

    context(:borda) {
      def wait_for_sortable
        expect(page).to(have_button(text: 'Submit Choices'))
      end

      def rearrange_choices(order)
        wait_for_sortable
        values = page.evaluate_script('Poll.sortable.toArray()')
        expect(values.length).to(be(order.length))
        expect(order.uniq.length).to(be(order.length))
        expect(order.uniq.sort.max).to(be(order.length - 1))
        values = order.map { |position| values[position] }
        page.execute_script("Poll.sortable.sort(#{values})")
        page.execute_script('Poll.updateScores()')
      end

      context(:borda_single) {
        let(:type) { :borda_single }

        it('submits a poll response') {
          go(poll.url)
          expect_expiration_text

          # Rearrange our choices.
          rearrange_choices([1, 0, 6, 3, 2, 5, 4])
          wait_for_sortable

          # Click on title to remove focus from any form input.
          find('h1').click
          goldens.verify('view_borda_single')

          # Confirm reload to viewing poll after responding.
          expect_responded_slim
          click_button('Submit Choices')
        }
      }

      context(:borda_split) {
        let(:type) { :borda_split }

        def drag_to_bottom(choice)
          wait_for_sortable
          choice_node = find(
              :xpath,
              "//li[@class='choice' and ./p[normalize-space()='#{choice}']]")
          choice_node.drag_to(find('ul#bottom-choices'))
        end

        it('shows an empty borda_split page') {
          go(poll.url)
          goldens.verify('view_borda_split_empty_bottom')
        }

        it('submits a poll response') {
          go(poll.url)
          expect_expiration_text

          # Drag a couple choices to the bottom red section.
          drag_to_bottom('two')
          drag_to_bottom('three')

          # Rearrange our remaining selected choices.
          rearrange_choices([1, 4, 0, 3, 2])
          wait_for_sortable

          # Click on title to remove focus from any form input.
          find('h1').click
          goldens.verify('view_borda_split')

          # Confirm reload to viewing poll after responding.
          expect_responded_slim
          click_button('Submit Choices')
        }
      }
    }

    context(:choose) {
      let(:type) { :choose_one }

      it('submits a poll response') {
        go(poll.url)
        expect_expiration_text

        # Get a screenshot of all our choices.
        goldens.verify('view_choose')

        # Confirm reload to viewing poll after responding.
        expect_responded_slim
        click_button('three')
      }
    }
  }

  context(:responded) {
    let(:poll) {
      create_poll(email: "#{type}@responded.com",
                  title: "#{type}_title",
                  question: "#{type}_question",
                  type: type)
    }
    let(:member) { poll.creating_member }

    before(:each) {
      set_cookie(:email, poll.email)
      %w[zero one two three four five six].each { |choice|
        poll.add_choice(text: choice)
      }
    }

    shared_examples('borda response') {
      it('shows a responded page') {
        choices.each_with_index { |position, rank|
          choice = poll.choices[position]
          member.add_response(choice_id: choice.id,
                              data: { score: score_calculation.call(rank) })
        }
        go(poll.url)
        goldens.verify("responded_#{type}")
      }
    }

    context(:borda_single) {
      let(:type) { :borda_single }
      let(:choices) { [3, 5, 1, 2, 0, 4, 6] }
      let(:score_calculation) {
        ->(rank) { poll.choices.length - rank - 1 }
      }

      it_has_behavior('borda response')
    }

    context(:borda_split) {
      let(:type) { :borda_split }
      let(:choices) { [3, 5, 1, 6] }
      let(:score_calculation) {
        ->(rank) { poll.choices.length - rank }
      }

      it_has_behavior('borda response')
    }

    context(:choose) {
      let(:type) { :choose_one }
      let(:choice) { poll.choices[3] }

      it('shows a responded page') {
        member.add_response(choice_id: choice.id)
        go(poll.url)
        goldens.verify('responded_choose')
      }
    }
  }

  context(:finished) {
    let(:poll) {
      create_poll(email: "#{type}@finished.com",
                  title: "#{type}_title",
                  question: "#{type}_question",
                  type: type)
    }
    let(:group) { poll.group }
    let(:members) {
      Array.new(6).fill { |i|
        group.add_member(email: "#{type}_#{i}@finished.com")
      }
    }
    let(:choices) {
      %w[zero one two three four five six].to_h { |choice|
        [choice, poll.add_choice(text: choice)]
      }
    }

    before(:each) {
      set_cookie(:email, poll.email)
    }

    shared_examples('finish') {
      before(:each) {
        responses.each_with_index { |ranked_choices, index|
          member = members[index]
          ranked_choices.each_with_index { |choice, rank|
            member.add_response(
                choice_id: choices[choice].id,
                data: { score: score_calculation.call(rank) })
          }
        }
        freeze_time(future + 1.day)
        go(poll.url)
      }

      it('shows a finished page') {
        goldens.verify("finished_#{type}")
      }

      it('shows a finished page with expanded summaries') {
        summary_expansions.each { |summary_pos|
          all('summary')[summary_pos].click
        }
        goldens.verify("finished_#{type}_expanded")
      }
    }

    context(:borda_single) {
      let(:type) { :borda_single }
      let(:responses) {
        [
          %w[zero one two three four five six],
          %w[five six zero one two three four],
          %w[five six zero three four one two],
          %w[five three four six zero one two],
          %w[two five three four six zero one]
        ]
      }
      let(:score_calculation) {
        ->(rank) { poll.choices.length - rank - 1 }
      }
      let(:summary_expansions) { [1, 3] }

      it_has_behavior('finish')
    }

    context(:borda_split) {
      let(:type) { :borda_split }
      let(:responses) {
        [
          %w[zero one two three],
          %w[five six zero one two],
          %w[five six zero],
          %w[five three four six zero one],
          %w[zero one]
        ]
      }
      let(:score_calculation) {
        ->(rank) { poll.choices.length - rank }
      }
      let(:summary_expansions) { [2, 8] }

      it_has_behavior('finish')
    }

    context(:choose) {
      let(:type) { :choose_one }
      let(:responses) {
        [
          %w[zero],
          %w[two],
          %w[two],
          %w[five],
          %w[zero]
        ]
      }
      let(:score_calculation) { ->(_) {} }
      let(:summary_expansions) { [1] }

      it_has_behavior('finish')
    }
  }
}

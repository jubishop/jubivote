require_relative 'shared_examples/entity_flows'

RSpec.describe(Group, type: :feature) {
  let(:goldens) { Tony::Test::Goldens::Page.new(page, 'spec/goldens/group') }

  let(:entity) { create_group }
  it_has_behavior('entity flows')

  context(:create) {
    it('creates a group') {
      # Visit group creation page.
      set_cookie(:email, 'group@create.com')
      go('/group/create')
      goldens.verify('create_empty')

      # Fill in a name and add some group members
      fill_in('name', with: 'group name')

      # Sometimes click Add button, sometimes press enter on input field.
      click_button('Add Member')
      6.times { |index|
        email = "group_#{index + 1}@create.com"
        if index.even?
          all('input.text').last.fill_in(with: email)
          click_button('Add Member')
        else
          all('input.text').last.fill_in(with: "#{email}\n")
        end
      }

      # Delete last empty field and "group_two@create.com"
      all('li.listable div').last.click
      all('li.listable div')[2].click

      # Ensure clicking Add button and pressing enter do nothing when there's
      # already an empty field.
      all('input.text')[1].fill_in(with: '')
      click_button('Add Member')
      all('input.text')[4].native.send_keys(:enter)

      # Ensure clicking Add button and pressing enter when there's an invalid
      # email does nothing
      all('input.text')[1].fill_in(with: 'invalid')
      click_button('Add Member')
      all('input.text')[4].native.send_keys(:enter)

      # Replace the now empty field ("group_1") with "group_7".
      all('input.text')[1].fill_in(with: 'group_7@create.com')

      # Click on title to remove focus from any form input.
      find('h1').click
      goldens.verify('create')

      # Confirm redirect to viewing group after creation.
      expect_slim(
          'group/view',
          group: an_instance_of(Models::Group),
          member: an_instance_of(Models::Member))
      click_button('Create Group')
    }
  }
}

require 'test_helper'
require "minitest/rails/capybara"

class SendInvitationTest < Capybara::Rails::TestCase
  setup do
    @conference = create(:conference)
    @admin = create(:user, person: create(:person), role: 'admin')
    @user = create(:user, person: create(:person), role: 'submitter')

    ActionMailer::Base.deliveries.clear
  end

  teardown do
    ActionMailer::Base.deliveries.clear
  end

  test 'admin can invite non platform users' do
    login_as(@admin)

    click_on 'Invites'

    within '#invitations-form' do
      fill_in 'email', with: 'user@email.com'
      click_on 'Send'
    end

    assert_equal 1, ActionMailer::Base.deliveries.size
    assert_text 'We have sent an invite to user@email.com'
  end

  test 'emails from admin invites do not contain neither blank spaces nor capital letters' do
    login_as(@admin)

    click_on 'Invites'

    within '#invitations-form' do
      fill_in 'email', with: ' uSeR@email.com '
      click_on 'Send'
    end

    invite = Invite.last

    assert_equal invite.email, 'user@email.com'
  end

  test 'admin receives feedback when an invitation is sent' do
    login_as(@admin)
    go_to_conference_person_profile(@conference, @user.person)

    click_on 'Send invitation'

    assert_equal 1, ActionMailer::Base.deliveries.size
    assert_text 'Person was invited.'
  end

  test 'admin receives feedback when an invitation is sent twice' do
    login_as(@admin)
    go_to_conference_person_profile(@conference, @user.person)
    click_on 'Send invitation'

    click_on 'Send invitation'

    assert_equal 2, ActionMailer::Base.deliveries.size
    assert_text "This person was already invited but we've sent the invitation again."
  end

  test 'invited users can send invitations to the conference by email' do
    create(:call_for_participation, conference: @conference)
    create(:invite, email: @user.person.email, person: @admin.person, conference: @conference, sharing_allowed: true)
    create(:attendance_status, person: @user.person, conference: @conference, status: AttendanceStatus::INVITED)

    with_user_invites_enabled do
      login_as(@user)

      within '#invitations-form' do
        fill_in 'email', with: 'user@email.com'
        click_on 'Send'
      end

      assert_equal 1, ActionMailer::Base.deliveries.size
      assert_text 'We have sent an invite to user@email.com'
    end
  end

  test 'invited users holding a ticket can send invitations to the conference by email' do
    create(:call_for_participation, conference: @conference)
    create(:invite, email: @user.person.email, person: @admin.person, conference: @conference, sharing_allowed: true)
    create(:attendance_status, person: @user.person, conference: @conference, status: AttendanceStatus::REGISTERED)

    with_user_invites_enabled do
      login_as(@user)

      within '#invitations-form' do
        fill_in 'email', with: 'user@email.com'
        click_on 'Send'
      end

      assert_equal 1, ActionMailer::Base.deliveries.size
      assert_text 'We have sent an invite to user@email.com'
    end
  end

  test 'users cannot send invites if the user invites are disabled' do
    create(:call_for_participation, conference: @conference)
    create(:invite, email: @user.person.email, person: @admin.person, conference: @conference, sharing_allowed: true)
    create(:attendance_status, person: @user.person, conference: @conference, status: AttendanceStatus::INVITED)

    with_user_invites_disabled do
      login_as(@user)
      assert_no_selector '#invitations-form'
    end
  end

  test 'emails in user invites do not contain neither blank spaces nor capital letters' do
    create(:call_for_participation, conference: @conference)
    create(:invite, email: @user.person.email, person: @admin.person, conference: @conference, sharing_allowed: true)
    create(:attendance_status, person: @user.person, conference: @conference, status: AttendanceStatus::INVITED)

    with_user_invites_enabled do
      login_as(@user)

      within '#invitations-form' do
        fill_in 'email', with: ' uSeR@email.com '
        click_on 'Send'
      end
    end

    invite = Invite.last
    assert_equal invite.email, 'user@email.com'
  end

  test 'users holding a ticket keep their attendance status if invited by admin' do
    create(:call_for_participation, conference: @conference)
    create(:invite, email: @user.person.email, person: @admin.person, conference: @conference, sharing_allowed: true)
    create(:attendance_status, person: @user.person, conference: @conference, status: AttendanceStatus::REGISTERED)

    login_as(@admin)
    go_to_conference_person_profile(@conference, @user.person)

    click_on 'Send invitation'

    assert_equal AttendanceStatus::REGISTERED, AttendanceStatus.find_by(person: @user.person, conference: @conference).status
  end

  # test 'users can request invitation to the conference' do
  #   create(:call_for_participation, conference: @conference)
  #
  #   login_as(@user)
  #
  #   within '#request_invitation' do
  #     click_on 'Request Invite'
  #   end
  #
  #   assert_equal 1, ActionMailer::Base.deliveries.size
  #   assert_text 'Your ticket request has been received.'
  # end

  # test 'admin can accept a request invitation' do
  #   create(:call_for_participation, conference: @conference)
  #
  #   login_as(@user)
  #
  #   within '#request_invitation' do
  #     click_on 'Request Invite'
  #   end
  #
  #   click_on 'Logout'
  #
  #   login_as(@admin)
  #
  #   go_to_conference_person_profile(@conference, @user.person)
  #
  #   click_on 'Accept request'
  #
  #   assert_text 'Person was invited.'
  # end

  # test 'users invited by admin that they send a request invitation not have a extra invitations' do
  #   create(:call_for_participation, conference: @conference)
  #
  #   login_as(@user)
  #
  #   within '#request_invitation' do
  #     click_on 'Request Invite'
  #   end
  #
  #   click_on 'Logout'
  #
  #   login_as(@admin)
  #
  #   go_to_conference_person_profile(@conference, @user.person)
  #
  #   click_on 'Accept request'
  #
  #   click_on 'Logout'
  #
  #   login_as(@user)
  #
  #   assert_no_text 'invites remaining.'
  # end

  test 'invited users have a limited number of invites' do
    create(:call_for_participation, conference: @conference)
    create(:invite, email: @user.person.email, person: @admin.person, conference: @conference, sharing_allowed: true)
    create(:attendance_status, person: @user.person, conference: @conference, status: AttendanceStatus::INVITED)

    number_of_invites = Invite::REGULAR_INVITES_PER_USER

    with_user_invites_enabled do
      login_as(@user)

      number_of_invites.times do |iteration|
        pending_invites = number_of_invites - iteration # starts with 0
        assert_text "You have #{pending_invites} invites remaining."

        within '#invitations-form' do
          fill_in 'email', with: "email#{iteration}@email.com"
          click_on 'Send'
        end
      end

      assert_text 'You have 0 invites remaining.'
    end
  end

  test 'users holding a ticket have a limited number of invites' do
    create(:call_for_participation, conference: @conference)
    create(:invite, email: @user.person.email, person: @admin.person, conference: @conference, sharing_allowed: true)
    create(:attendance_status, person: @user.person, conference: @conference, status: AttendanceStatus::REGISTERED)

    number_of_invites = Invite::REGULAR_INVITES_PER_USER

    with_user_invites_enabled do
      login_as(@user)

      number_of_invites.times do |iteration|
        pending_invites = number_of_invites - iteration # starts with 0
        assert_text "You have #{pending_invites} invites remaining."

        within '#invitations-form' do
          fill_in 'email', with: "email#{iteration}@email.com"
          click_on 'Send'
        end
      end

      assert_text 'You have 0 invites remaining.'
    end
  end

  test 'invited users can be granted a specific number of invites' do
    create(:call_for_participation, conference: @conference)
    create(:invite, email: @user.person.email, person: @admin.person, conference: @conference, sharing_allowed: true)
    create(:attendance_status, person: @user.person, conference: @conference, status: AttendanceStatus::INVITED)

    number_of_invites = 100
    InvitesAssignation.create(person: @user.person, conference: @conference, number: number_of_invites)

    with_user_invites_enabled do
      login_as(@user)
      assert_text "You have #{number_of_invites} invites remaining."
    end
  end

  test 'users holding a ticket can be granted a specific number of invites' do
    create(:call_for_participation, conference: @conference)
    create(:invite, email: @user.person.email, person: @admin.person, conference: @conference, sharing_allowed: true)
    create(:attendance_status, person: @user.person, conference: @conference, status: AttendanceStatus::REGISTERED)

    number_of_invites = 100
    InvitesAssignation.create(person: @user.person, conference: @conference, number: number_of_invites)

    with_user_invites_enabled do
      login_as(@user)
      assert_text "You have #{number_of_invites} invites remaining."
    end
  end

  test 'invited users can be granted packages of 5 additional invitations' do
    create(:call_for_participation, conference: @conference)
    create(:invite, email: @user.person.email, person: @admin.person, conference: @conference, sharing_allowed: true)
    create(:attendance_status, person: @user.person, conference: @conference, status: AttendanceStatus::INVITED)

    login_as(@admin)

    go_to_conference_person_profile(@conference, @user.person)
    click_on 'Assign +5 invitations'
    click_on 'Logout'

    with_user_invites_enabled do
      login_as(@user)
      assert_text 'You have 10 invites remaining.'
    end
  end

  test 'users holding a ticket can be granted packages of 5 additional invitations' do
    create(:call_for_participation, conference: @conference)
    create(:invite, email: @user.person.email, person: @admin.person, conference: @conference, sharing_allowed: true)
    create(:attendance_status, person: @user.person, conference: @conference, status: AttendanceStatus::REGISTERED)

    login_as(@admin)

    go_to_conference_person_profile(@conference, @user.person)
    click_on 'Assign +5 invitations'
    click_on 'Logout'

    with_user_invites_enabled do
      login_as(@user)
      assert_text 'You have 10 invites remaining.'
    end
  end

  test 'uninvited users cannot be granted packages of 5 additional invitations' do
    create(:call_for_participation, conference: @conference)

    login_as(@admin)

    go_to_conference_person_profile(@conference, @user.person)

    assert_no_text 'Assign +5 invitations'
  end

  test 'user available invites cannot be less than zero' do
    create(:call_for_participation, conference: @conference)
    create(:invite, email: @user.person.email, person: @admin.person, conference: @conference, sharing_allowed: true)

    number_of_invites = -100
    InvitesAssignation.create(person: @user.person, conference: @conference, number: number_of_invites)

    with_user_invites_enabled do
      login_as(@user)
      assert_text 'You have 0 invites remaining.'
    end
  end

  test 'users cannot invite people already invited' do
    same_email = 'user@email.com'
    create(:call_for_participation, conference: @conference)
    create(:invite, email: @user.person.email, person: @admin.person, conference: @conference, sharing_allowed: true)
    create(:attendance_status, person: @user.person, conference: @conference, status: AttendanceStatus::INVITED)
    create(:invite, email: same_email, conference: @conference)

    with_user_invites_enabled do
      login_as(@user)

      within '#invitations-form' do
        fill_in 'email', with: same_email
        click_on 'Send'
      end

      assert_equal 0, ActionMailer::Base.deliveries.size
      assert_text 'The user you are trying to invite has already received an invite'
    end
  end

  # test 'users that requested invitation can not invite other people' do
  #   create(:call_for_participation, conference: @conference)
  #
  #   login_as(@user)
  #
  #   within '#request_invitation' do
  #     click_on 'Request Invite'
  #   end
  #
  #   assert_text 'Your ticket request has been received.'
  #   click_on 'Logout'
  #
  #   login_as(@admin)
  #   go_to_conference_person_profile(@conference, @user.person)
  #   click_on 'Accept request'
  #   click_on 'Logout'
  #
  #   login_as(@user)
  #   assert_no_text 'invites remaining.'
  # end

  test 'users invited from admin panel can invite other people' do
    create(:call_for_participation, conference: @conference)

    login_as(@admin)
    go_to_conference_person_profile(@conference, @user.person)
    click_on 'Send invitation'
    click_on 'Logout'

    with_user_invites_enabled do
      login_as(@user)
      assert_text 'You have 5 invites remaining.'
    end
  end

  test 'users invited from user portal cannot invite other people' do
    create(:call_for_participation, conference: @conference)

    login_as(@admin)
    go_to_conference_person_profile(@conference, @user.person)
    click_on 'Send invitation'
    click_on 'Logout'

    other_user = create(:user, person: create(:person))

    with_user_invites_enabled do
      login_as(@user)
      within '#invitations-form' do
        fill_in 'email', with: other_user.person.email
        click_on 'Send'
      end
      click_on 'Logout'

      login_as(other_user)

      assert_no_selector '#invitations-form'
    end
  end

  test 'person can access to the invitation link' do
    invite = create(:invite, email: @user.person.email, conference: @conference)

    login_as(@user)

    visit "/#{@conference.acronym}/invitations/#{invite.id}/ticketing_form"

    assert_text "#{@conference.alt_title} Ticket"
  end

  test 'person cannot access to other conferences with same invitation' do
    other_conference = create(:conference)
    other_invited = create(:invite, email: @user.person.email, conference: other_conference)

    login_as(@user)

    visit "/#{@conference.acronym}/invitations/#{other_invited.id}/ticketing_form"

    assert_text 'You cannot register to the conference without an invitation'
  end

  test 'not logged person cannot access get ticket form' do
    invite = create(:invite, conference: @conference)

    visit "/#{@conference.acronym}/invitations/#{invite.id}/ticketing_form"

    assert_text 'Please register to be able to'
  end

  test 'other persons cannot access to other invitation links' do
    invite = create(:invite, person: @user.person, conference: @conference)
    @non_invited_person = create(:user, role: 'submitter')

    login_as(@non_invited_person)

    visit "/#{@conference.acronym}/invitations/#{invite.id}/ticketing_form"

    assert_text 'You cannot register to the conference without a valid invitation'
  end

  test 'invitation must exists' do
    wrong_invite_id = '123'

    login_as(@user)

    visit "/#{@conference.acronym}/invitations/#{wrong_invite_id}/ticketing_form"

    assert_text 'You cannot register to the conference without a valid invitation'
  end

  private

  def login_as(user)
    visit '/'

    within '#login' do
      fill_in 'user_email', with: user.email
      fill_in 'user_password', with: user.password

      click_on 'Sign in'
    end
  end

  def go_to_conference_person_profile(conference, person)
    visit "/#{conference.acronym}/people"

    click_on person.public_name
  end

  def go_to_user_portal(conference, person)
    visit "/#{conference.acronym}/cfp"
  end
end

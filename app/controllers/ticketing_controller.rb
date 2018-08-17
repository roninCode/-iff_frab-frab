class TicketingController < ApplicationController
  before_action :authenticate_user!
  before_action :require_same_person
  before_action :require_invitation

  before_action :no_previous_ticket, only: [:register_ticket]

  def ticketing_form
    @person = Person.find(params[:id])
  end

  def register_ticket
    id = params[:id]
    acronym = params[:conference_acronym]
    attributes = params[:person]

    @person = Person.find(id)
    @conference = Conference.find_by(acronym: acronym)

    @person.public_name = attributes['public_name']
    @person.gender_pronoun = attributes['gender_pronoun']
    @person.iff_before = attributes['iff_before']
    @person.iff_goals = attributes['iff_goals']
    @person.interested_in_volunteer = attributes['interested_in_volunteer']
    @person.iff_days = attributes['iff_days']

    errors = validate_required_ticket_fields(attributes)
    unless errors.empty?
      flash[:error] = "You cannot get a ticket without #{errors.join(', ')}"
      render 'ticketing_form'
      return
    end

    @person.save!

    Attendee.create(person: @person, conference: @conference, status: 'invited')

    redirect_to cfp_root_path, notice: "You've been succesfuly registered"
  end

  private

  REQUIRED_FIELDS = {
    public_name: 'public name',
    gender_pronoun: 'gender pronoun',
    iff_before: 'past editions',
    iff_goals: 'goals',
    iff_days: 'attendance days'
  }

  def validate_required_ticket_fields(values)
    errors = []

    REQUIRED_FIELDS.each do |field, error|
      value = values[field]

      if value.nil? || value.blank?
        errors << error
      end
    end

    errors
  end

  def require_same_person
    person = Person.find(params[:id])

    if current_user.person.nil? || person.id != current_user.person.id
      flash[:error] = 'You cannot register to the conference without a valid invitation'
      redirect_to cfp_root_path
    end
  end

  def require_invitation
    person = Person.find(params[:id])
    conference = Conference.find_by(acronym: params[:conference_acronym])

    unless Invited.exists?(person_id: person.id, conference_id: conference.id)
      flash[:error] = 'You cannot register to the conference without an invitation'
      redirect_to cfp_root_path
    end
  end

  def no_previous_ticket
    person = Person.find(params[:id])
    conference = Conference.find_by(acronym: params[:conference_acronym])

    if Attendee.exists?(person_id: person.id, conference_id: conference.id)
      flash[:error] = 'You cannot register to the conference twice'
      redirect_to cfp_root_path
    end
  end
end

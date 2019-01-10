class EventsController < ApplicationController
  before_action :authenticate_user!
  before_action :not_submitter!
  after_action :restrict_events

  # GET /events
  # GET /events.xml
  def index
    authorize! :read, Event
    @person = current_user.person
    @events = search @conference.events.includes(:track), params
    clean_events_attributes
    respond_to do |format|
      format.html {
        @events = @events.paginate page: page_param
      }
      format.xml  { render xml: @events }
      format.json { render json: @events }
      format.csv  { send_data @events.to_csv, filename: "events-#{Date.today}.csv" }
    end
  end

  def export_accepted
    authorize! :read, Event
    @events = @conference.events.is_public.accepted

    respond_to do |format|
      format.json { render :export }
    end
  end

  def grant_dif
    authorize! :administrate, Person
    event = Event.find(params[:id])
    event.update(dif_status: "Granted")
    person = event.event_people.find_by(event_role: "submitter").person
    redirect_to(person_path(conference_acronym: @conference.acronym, id: person.id), notice: 'Dif Granted!')
  end

  def export_confirmed
    authorize! :read, Event
    @events = @conference.events.is_public.confirmed

    respond_to do |format|
      format.json { render :export }
    end
  end

  # current_users events
  def my
    authorize! :read, Event

    result = search @conference.events.associated_with(current_user.person), params
    clean_events_attributes
    @events = result.paginate page: page_param
  end

  # events as pdf
  def cards
    authorize! :crud, Event
    if params[:accepted]
      @events = @conference.events.accepted
    else
      @events = @conference.events
    end

    respond_to do |format|
      format.pdf
    end
  end

  # show event ratings
  def ratings
    authorize! :create, EventRating

    result = search @conference.events, params
    @events = result.paginate page: page_param
    clean_events_attributes

    # total ratings:
    @events_total = @conference.events.count
    @events_reviewed_total = @conference.events.to_a.count { |e| !e.event_ratings_count.nil? && e.event_ratings_count > 0 }
    @events_no_review_total = @events_total - @events_reviewed_total

    # current_user rated:
    @events_reviewed = @conference.events.joins(:event_ratings).where('event_ratings.person_id' => current_user.person.id).count
    @events_no_review = @events_total - @events_reviewed
  end

  # show event feedbacks
  def feedbacks
    authorize! :access, :event_feedback
    result = search @conference.events.accepted, params
    @events = result.paginate page: page_param
  end

  # start batch event review
  def start_review
    authorize! :create, EventRating
    ids = Event.ids_by_least_reviewed(@conference, current_user.person)
    if ids.empty?
      redirect_to action: 'ratings', notice: 'You have already reviewed all events:'
    else
      session[:review_ids] = ids
      redirect_to event_event_rating_path(event_id: ids.first)
    end
  end

  # GET /events/1
  # GET /events/1.xml
  def show
    @event = Event.find(params[:id])
    authorize! :read, @event
    event_person = EventPerson.find_by(event_id: @event.id)
    @submitter = Person.find_by(id: event_person.person_id)

    clean_events_attributes
    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render xml: @event }
      format.json { render json: @event }
    end
  end

  # people tab of event detail page, the rating and
  # feedback tabs are handled in routes.rb
  # GET /events/2/people
  def people
    @event = Event.find(params[:id])
    authorize! :read, @event
  end

  # GET /events/new
  def new
    authorize! :crud, Event
    @event = Event.new
    @start_time_options = @conference.start_times_by_day

    respond_to do |format|
      format.html # new.html.erb
    end
  end

  # GET /events/1/edit
  def edit
    @event = Event.find(params[:id])
    authorize! :update, @event

    @start_time_options = @event.possible_start_times
  end

  # GET /events/2/edit_people
  def edit_people
    @event = Event.find(params[:id])
    # @persons = Person.fullname_options

    authorize! :update, @event
  end

  # POST /events
  def create
    @event = Event.new(form_params)
    @event.conference = @conference
    authorize! :create, @event
    respond_to do |format|
      if @event.save
        EventPerson.create(event_id: @event.id, person_id: current_user.person.id)
        format.html { redirect_to(@event, notice: 'Event was successfully created.') }
      else
        @start_time_options = @conference.start_times_by_day
        format.html { render action: 'new' }
      end
    end
  end

  # PUT /events/1
  def update

    authorize! :submit, Event
    event_values = prepare_params(form_params)
    event_values[:other_presenters] = remove_duplicates_of_other_presenters_list(event_values[:other_presenters])

    @event = Event.find(params[:id])
    # @event = current_user.person.events.readonly(false).find(params[:id])
    old_emails_list = @event.other_presenters

    event_valid = !invalid_presenters?(event_values[:other_presenters])

    respond_to do |format|
      if @event.update(form_params) && event_valid
        emails_list = valid_presenters(event_values[:other_presenters])
        create_role_if_not_exists(emails_list, @event, 'collaborator')
        new_emails_list = @event.other_presenters
        delete_role(old_emails_list, new_emails_list, @event)

        format.html { redirect_to(event_path(@event), notice: t('cfp.event_updated_notice')) }

      else
        flash[:alert] = "You must fill out all the required fields!"

        flash[:danger] = []

        if @event.errors.messages[:title]
          flash[:danger] << "There is already a session submitted with this title. Please review your title and make sure that the session is not already submitted."
        end

        if invalid_presenters?(event_values[:other_presenters])
          @invalid_list_of_emails = invalid_presenters_list(event_values[:other_presenters])
          wrong_emails_alert = "These emails does not exist in our database: " << @invalid_list_of_emails << ". Please, correct this. Remember emails can be separated by , or space."
          flash[:danger] <<  wrong_emails_alert
          flash[:danger] << "It seems that the e-mail you inserted does not exist in our database. Please be sure the colleagues are registered platform users in order to be able to add them as event collaborators.
                            NOTE: This field is not mandatory and therefore you can add information about the collaborators later."
        end
        @edit = true
        @start_time_options = @event.possible_start_times
        format.html { render action: 'edit' }
      end
    end
  end

  # update event state
  # GET /events/2/update_state?transition=cancel
  def update_state
    @event = Event.find(params[:id])
    authorize! :update, @event

    if params[:send_mail]
      # We're managing our own emails, so we prevent the use of the integrated mailing for notifications
      params[:send_mail] = false

      # # If integrated mailing is used, take care that a notification text is present.
      # if @event.conference.notifications.empty?
      #   return redirect_to edit_conference_path, alert: 'No notification text present. Please change the default text for your needs, before accepting/ rejecting events.'
      # end

      # return redirect_to(@event, alert: 'Cannot send mails: Please specify an email address for this conference.') unless @conference.email

      # return redirect_to(@event, alert: 'Cannot send mails: Not all speakers have email addresses.') unless @event.speakers.all?(&:email)

      EventsMailer.accepted_event_email(@event).deliver_now
    end

    begin
      @event.send(:"#{params[:transition]}!", send_mail: params[:send_mail], coordinator: current_user.person)
    rescue => ex
      return redirect_to(@event, alert: "Cannot update state: #{ex}.")
    end

    if params[:transition] == "confirm"
      @event.update!(etherpad_url: "pad.internetfreedomfestival.org/p/#{@event.id}")
    end

    redirect_to @event, notice: 'Event was successfully updated.'
  end

  # add custom notifications to all the event's speakers
  # POST /events/2/custom_notification
  def custom_notification
    @event = Event.find(params[:id])
    authorize! :update, @event

    case @event.state
    when 'accepting'
      state = 'accept'
    when 'rejecting'
      state = 'reject'
    when 'confirmed'
      state = 'schedule'
    else
      return redirect_to(@event, alert: "Event not in a notifiable state.")
    end

    @event.event_people.presenter.each{ |p| p.set_default_notification(state) }

    redirect_to edit_people_event_path(@event)
  end

  # DELETE /events/1
  def destroy
    @event = Event.find(params[:id])
    authorize! :destroy, @event
    @event.destroy

    respond_to do |format|
      format.html { redirect_to(events_url) }
    end
  end

  private

  def prepare_params(form_params)
    event_values = form_params.merge(
      recording_license: @conference.default_recording_license,
    )
    event_values
  end

  def remove_duplicates_of_other_presenters_list(list)
    return "" if list.nil?
    extract_emails_from(list).reject(&:empty?).uniq.join(',')
  end

  def extract_emails_from(string)
    valid_separators = /[\s,]/
    emails = string.split(valid_separators)

    emails
  end

  def invalid_presenters?(presenters)
    return false if presenters.nil? || presenters.blank?

    email_list = extract_emails_from(presenters)

    email_list.each do |email|
      found = Person.find_by(email: email)
      if !found
        return true
      end
    end
    false
  end

  def valid_presenters(presenters)
    email_list = extract_emails_from(presenters)

    email_list.select do |email|
      Person.find_by(email: email)
    end
  end

  def create_role_if_not_exists(emails_list, event, role)
    emails_list.map do |email|
      person = Person.find_by(email: email)

      unless EventPerson.exists?(person: person, event: event, event_role: role)
        register_for_proposal(person, event, role)
      end
    end
  end

  def delete_role(old_emails_list, new_emails_list, event)
    emails_to_delete = extract_emails_from(old_emails_list) - extract_emails_from(new_emails_list)

    emails_to_delete.map do |email|
      Rails.logger.info "deleting email #{email}"
      person = EventPerson.find_by(person: Person.find_by(email: email), event: event, event_role: 'collaborator')
      person.destroy if person
    end
  end

  def register_for_proposal(person, event, role)
    EventPerson.create(person: person, event: event, event_role: role)
    EventsMailer.create_event_mail(person.email, event).deliver_now
  end

  def invalid_presenters_list(presenters)
    return [] if presenters.nil? || presenters.blank?

    invalid_list_of_emails = []
    email_list = extract_emails_from(presenters)
    email_list.each do |email|
      found = Person.find_by(email: email)
      if found.nil?
        invalid_list_of_emails << email
      end
    end

    return invalid_list_of_emails.reject(&:blank?).join(", ")
  end

  def restrict_events
    @events = @events.accessible_by(current_ability) unless @events.nil?
  end

  def clean_events_attributes
    return if can? :crud, Event
    @event.clean_event_attributes! unless @event.nil?
    @events.map(&:clean_event_attributes!) unless @events.nil?
  end

  def search(events, params)
    filter = events
    filter = filter.where(state: params[:event_state]) if params[:event_state].present?
    filter = filter.where(event_type: params[:event_type]) if params[:event_type].present?
    filter = filter.where(track: @conference.tracks.find_by(:name => params[:track_name])) if params[:track_name].present?

    if params.key?(:term) and not params[:term].empty?
      term = params[:term]
      sort = begin
               params[:q][:s]
             rescue
               nil
             end
      @search = filter.ransack(title_cont: term,
                               description_cont: term,
                               abstract_cont: term,
                               track_name_cont: term,
                               event_type_is: term,
                               m: 'or',
                               s: sort)
    else
      @search = filter.ransack(params[:q])
    end

    @search.result(distinct: true)
  end

  # def event_params
  #   params.require(:event).permit(
  #     :id, :title, :subtitle, :event_type, :time_slots, :state, :start_time, :public, :language, :abstract, :description, :logo, :track_id, :room_id, :note, :submission_note, :do_not_record, :recording_license, :other_presenters, :public_type, :tech_rider,
  #     :desired_outcome, :phone_number, :track_id, {iff_before: []}, :projector, event_attachments_attributes: %i(id title attachment public _destroy),
  #     ticket_attributes: %i(id remote_ticket_id),
  #     links_attributes: %i(id title url _destroy),
  #     event_people_attributes: %i(id person_id event_role role_state notification_subject notification_body _destroy)
  #   )
  # end

  def form_params
    params.require(:event).permit(:id, :title, :state, :language, :subtitle,
      :other_presenters, :description, :target_audience, :abstract,
      :submission_note, :do_not_record, :recording_license, :tech_rider,
      :desired_outcome, :phone_number, :track_id, :event_type, :start_time, :room_id, :note,
      :projector, {iff_before: []}, :instructions, :travel_assistance, :group,
      :recipient_travel_stipend, {travel_support: []}, {past_travel_assistance: []},
      :understand_one_presenter, :confirm_not_stipend, :code_of_conduct, :time_slots,
      :public)
  end
end

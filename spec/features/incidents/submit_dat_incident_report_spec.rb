require 'spec_helper'

describe "DAT Incident Report", type: :feature, versions: true do
  #self.use_transactional_fixtures = false

  it "Should be submittable" do
    grant_role! 'submit_incident_report'

    @chapter = @person.chapter
    FactoryGirl.create :incidents_scope, chapter: @person.chapter

    @team_lead = FactoryGirl.create :person, chapter: @person.chapter, counties: @person.counties
    @responder = FactoryGirl.create :person, chapter: @person.chapter, counties: @person.counties
    @flex_responder = FactoryGirl.create :person, chapter: @person.chapter, counties: @person.counties

    @vehicle = FactoryGirl.create :vehicle, chapter: @chapter

    FactoryGirl.create :flex_schedule, person: @flex_responder

    @incident = FactoryGirl.create :raw_incident, chapter: @person.chapter, area: @person.counties.first

    navigate_to_incident
    #visit "/incidents/incidents/#{@incident.incident_number}/dat/new"

    fill_in_details

    click_link "Go to Responders Page"

    fill_in_responders

    click_link "Go to Services Page"

    fill_in_services

    click_button 'Submit Incident Information'
    click_link "Details"
    expect(page).to have_text 'DAT Details'
    expect(page).to have_text 'Demographics'

    expect(@incident.reload.dat_incident).not_to be_nil
    expect(@incident.all_responder_assignments.size).to eq(3)
    expect(@incident.all_responder_assignments.map(&:person)).to match_array([@team_lead, @responder, @flex_responder])

    expect(@incident.address).to eq("1663 Market Street")
    expect(@incident.status).to eq('closed')

  end

  def navigate_to_incident
    visit "/incidents/#{@chapter.url_slug}"

    click_link "Submit Incident Report"
    within :xpath, "//td[text()='#{@incident.incident_number}']/ancestor::tr" do
      click_link "Submit Incident Information"
    end
  end

  def fill_in_details

    select 'Flood', from: 'Incident type*'
    select 'Cold', from: 'Incident call type*'

    fill_in 'Num adults*', with: 1
    fill_in 'Num children*', with: 1
    fill_in 'Num families*', with: 1
    fill_in 'Num people injured*', with: 1
    fill_in 'Num people hospitalized*', with: 1
    fill_in 'Num people deceased*', with: 1

    fill_in 'Search for address', with: '1663 Market St San Francisco'
    click_button 'Look Up Address'

    select 'Apartment', from: 'Structure type*'
    fill_in 'Units affected*', with: 1
    fill_in 'Units minor*', with: 1
    fill_in 'Units major*', with: 1
    fill_in 'Units destroyed*', with: 1

    # Need the times here
    t = @chapter.time_zone.now
    fill_in_responder_timeline("#incidents_dat_incident_incident_attributes_timeline_attributes_dat_received_attributes_event_time", t)
    fill_in_responder_timeline("#incidents_dat_incident_incident_attributes_timeline_attributes_dat_on_scene_attributes_event_time", t.advance( hours: 1))
    fill_in_responder_timeline("#incidents_dat_incident_incident_attributes_timeline_attributes_dat_departed_scene_attributes_event_time", t.advance( hours: 3))
  end

  def fill_in_responder_timeline(element, time)
    find(element).click

    day = time.day.to_s
    hour = time.hour.to_s
    minute = hour + ":" + (time.min - (time.min % 5)).to_s

    within(".datetimepicker") do
        3.times { find('.active').click }
    end

  end

  def fill_in_responders
    fill_in 'incidents_dat_incident_incident_attributes_team_lead_attributes_person_id_text', with: @team_lead.first_name[0..4]
    find('.tt-suggestion', text: @team_lead.full_name).click

    # Add the flex person
    within :xpath, "//td[text()='#{@flex_responder.full_name.gsub "'", "\\'"}']/.." do
      click_button "Add Responder"
    end

    within "#responder-table tbody" do
      within "tr:last-child" do
        expect(find(:xpath, ".//input[@type='checkbox']")).to be_checked
        select 'Responder'
      end
    end

    # Add the regular person
    first("a", text: "Add Other Responder").click
    within "#responder-table tbody" do
      within "tr:last-child" do
        fill_in 'person_text', with: @responder.first_name
        find('p', text: @responder.full_name).click

        expect(find(:xpath, ".//input[@type='checkbox']")).not_to be_checked
        select 'Team Lead Trainee'
      end
    end
  end

  def fill_in_services
    fill_in 'Narrative*', with: 'This is my narrative'
    check 'Food'
    check 'Translation'
    check 'Spanish'

    check 'Meal Served'
    fill_in '# of Meals Served*', with: 100
    fill_in 'incidents_dat_incident_incident_attributes_incident_id_feeding_partner_use_text', with: 'McDonalds'

    check 'Evacuation Center Opened'
    fill_in 'incidents_dat_incident_incident_attributes_incident_id_evac_partner_use_text', with: "Bill Graham"
    find(".tt-suggestion", text: 'New').click

    check 'Shelter Opened'
    fill_in 'incidents_dat_incident_incident_attributes_incident_id_shelter_partner_use_text', with: 'YMCA'
    find(".tt-suggestion", text: 'New').click
    
    check 'Hotel/Motel Provided'
    fill_in 'incidents_dat_incident_incident_attributes_incident_id_hotel_partner_use_text', with: 'Holiday Inn'
    fill_in 'Hotel rate*', with: 129.00
    fill_in 'Rooms Booked*', with: 1

    fill_in 'Comfort kits*', with: 10
    fill_in 'Blankets*', with: 20

    select @vehicle.name, from: "Vehicle"
    click_button 'Add Another Vehicle'
  end
end
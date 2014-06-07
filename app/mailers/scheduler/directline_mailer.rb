require 'csv'

class Scheduler::DirectlineMailer < ActionMailer::Base
  include MailerCommon
  default from: "DAT Scheduling <directline.export@dcsops.org>"

  # Subject can be set in your I18n file at config/locales/en.yml
  # with the following lookup:
  #
  #   en.scheduler.reminders_mailer.email_invite.subject
  #

  def export(chapter, start_date, end_date)
    @chapter = chapter
    start_date = start_date.to_date
    end_date = end_date.to_date
    @people = []

    attachments["shift_data.csv"] = schedule_csv(start_date, end_date)
    attachments["roster.csv"] = people_csv

    tag :export
    mail to: chapter.scheduler_dispatch_export_recipient, subject: "Red Cross Export", body: "Export processed at #{Time.zone.now}"
  end

  private

  def schedule_csv(start_date, end_date)
    shift_data = CSV.generate(row_sep: "\r\n") do |csv|
      csv << ["County", "Start", "End", "On Call Person IDs"] + (1..20).map{|x| "On Call #{x}"}
      Scheduler::DispatchConfig.active.for_chapter(@chapter).includes{county.chapter}.each do |config|
        county = config.county
        chapter = @chapter

        @people = @people + config.backup_list
        generate_shifts_for_county(csv, chapter, county, config.name, start_date, end_date, config.backup_list.map(&:id))
      end
    end
  end

  def generate_shifts_for_county(csv, chapter, county, name, start_date, end_date, backups)
    @latest_time = nil
    daily_groups = Scheduler::ShiftGroup.where(chapter_id: chapter, period: 'daily').joins{shifts}.where{shifts.dispatch_role != nil}.order(:start_offset).uniq.to_a
    (start_date..end_date).each do |date|
      daily_groups.each do |daily_group|
        start_time = local_offset(chapter, date, daily_group.start_offset)
        end_time = local_offset(chapter, date, daily_group.end_offset)
        check_timing_overlap start_time, end_time
        
        assignments = assignments_for_period(chapter, county, daily_group, start_time)
        @people.concat assignments.map(&:person)
        person_list = assignments.map(&:person_id) + backups

        csv << ([name, start_time.iso8601, end_time.iso8601] + person_list)
      end
    end
  end

  def check_timing_overlap start_time, end_time
    if @latest_time and @latest_time > start_time
      raise "A configuration error has occurred and shifts are overlapping: New start is #{start_time.iso8601}, last end was #{latest_time.iso8601}"
    end
    @latest_time = end_time
  end


  def assignments_for_period(chapter, county, daily_group, start_time)
    other_groups = Scheduler::ShiftGroup.current_groups_for_chapter(chapter, start_time, Scheduler::ShiftGroup.includes{shifts})

    shifts = other_groups.flat_map{|grp| map_shifts grp, grp.start_date}
    shifts = shifts.select{|sh| sh[:shift].county_id == county.id }.sort_by{|sh| sh[:role]}

    assignments = shifts.map{|sh| Scheduler::ShiftAssignment.where(date: sh[:date], shift_id: sh[:shift], shift_group_id: sh[:group]).first }.compact
  end

  def map_shifts(group, date)
    group.shifts.select(&:dispatch_role).select{|sh| sh.active_on_day? date, group }.map do |shift|
      {shift: shift, date: date, role: shift.dispatch_role, group: group}
    end
  end

  def people_csv
    CSV.generate(row_sep: "\r\n") do |csv|
      csv << ["Person ID", "Last Name", "First Name", "Primary Phone", "Secondary Phone", "SMS Phone", "OnPage ID", "Email", "Primary Phone Type", "Secondary Phone Type"]
      @people.uniq.each do |person|
        phones = person.phone_order
        sms = person.phone_order(sms_only: true).first
        sms = nil if sms and sms[:carrier].pager
        csv << [person.id, person.last_name, person.first_name, format_phone(phones[0]), format_phone(phones[1]), format_phone(sms), "", "", phone_type(phones[0]), phone_type(phones[1])] 
      end
    end
  end

  def format_phone(ph)
    ph && ph[:number].gsub(/[^0-9]/, '')
  end

  def phone_type(ph)
    (ph && ph[:carrier].try(:pager)) ? 'pager' : 'phone'
  end

  def local_offset(chapter, date, offset)
    beginning_of_day = date.in_time_zone(chapter.time_zone).at_beginning_of_day
    offset_time = beginning_of_day.advance seconds: offset

    # advance counts every instant that elapses, not just calendar seconds.  so
    # when crossing DST you might end up one hour off in either direction even though
    # you just want "wall clock" time.  So if the offset of the two times is different, we
    # negate it.
    offset_time.advance( seconds: (beginning_of_day.utc_offset - offset_time.utc_offset))
  end
end

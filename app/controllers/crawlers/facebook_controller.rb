module Crawlers
  class FacebookController < ApplicationController
    def self.search_events
      refresh_facebook_token

      fb_api = Koala::Facebook::API.new(Setting.facebook_access_token)
      fields = 'id,name,description,start_time,end_time,attending_count,'\
               'interested_count,place,updated_time'

      events = []

      Group.facebook.authorized.each do |group|
        event = {
          group: group,
          events: fb_api
          .get_object("/#{group.external_id}/events?fields=#{fields}"\
            "&since=#{12.months.ago.to_i}&until=#{1.year.from_now.to_i}")
        }
        events.push(event)
      end
      fetch_latest(events)
    rescue Koala::Facebook::AuthenticationError => e
      puts "FACEBOOK KOALA ERROR: #{e}"
      raise e
    rescue Exception => e
      puts "FACEBOOK ERROR: #{e}"
      raise e
    end

    private

    def self.refresh_facebook_token
      refresh_token_url = "https://graph.facebook.com/oauth/access_token?"\
                 "&client_id=#{ENV['FACEBOOK_APP_ID']}"\
                 "&client_secret=#{ENV['FACEBOOK_APP_SECRET']}"\
                 "&grant_type=fb_exchange_token"\
                 "&fb_exchange_token=#{Setting.facebook_access_token}"
      response = Rack::Utils.parse_nested_query HTTP.get(refresh_token_url).to_s
      Setting.facebook_access_token = response['access_token']
    end

    def self.fetch_latest(json_events)
      json_events.each do |events|
        group = Group.find_or_initialize_by(external_id: events[:group][:external_id])
        group.update(
          name: events[:group][:name],
          url: "https://www.facebook.com/groups/#{events[:group][:external_id]}/"
        )

        events[:events].each do |json|
          next if ['malaysia', 'my'].exclude?(json['place']
            .try(:[],'location').try(:[],'country').try(:downcase))

          event = Event.find_or_initialize_by(external_id: json['id'])
          
          next if event.last_updated == json['updated_time'].to_datetime

          event.update(event_params(json, group))
        end
      end
    end

    def self.event_params(json, group)
      location = json['place'].try(:[],'location')

      full_address =
        if location
          "#{location['street']}, #{location['zip']}, #{location['city']},
          #{location['state']}, #{location['country']}"
        else
          nil
        end

      location_attributes = {
        name: json['place']['name'],
        full_address: full_address,
        street: json['place'].try(:[],'location').try(:[],'street'),
        zip: json['place'].try(:[],'location').try(:[],'zip'),
        city: json['place'].try(:[],'location').try(:[],'city'),
        state: json['place'].try(:[],'location').try(:[],'state'),
        country: json['place'].try(:[],'location').try(:[],'country'),
        latitude: json['place'].try(:[],'location').try(:[],'latitude'),
        longitude: json['place'].try(:[],'location').try(:[],'longitude')
      } if json['place']

      event = {
        external_id: json['id'],
        url: "https://www.facebook.com/events/#{json['id']}/",
        name: json['name'],
        status: 'authorized',
        entry_type: 'automated',
        description: json['description'],
        start_time: json['start_time'].try(:to_datetime),
        end_time: json['end_time'].try(:to_datetime),
        group: group
      }
      event['location_attributes'] = location_attributes if location_attributes
      event
    end
  end
end

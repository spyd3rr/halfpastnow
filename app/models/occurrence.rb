class Occurrence < ActiveRecord::Base
  belongs_to :event
  belongs_to :recurrence, :dependent => :delete
  has_many :histories

  # Bi-directional bookmarks association (find a user's bookmarked events, and users who have bookmarked this event)
  belongs_to :bookmarked, :polymorphic => true
  has_many :bookmarks, :as => :bookmarked
  # Allows you to search for users that bookmarked this event by calling "event.bookmarked_by"
  has_many :bookmarked_by, :through => :bookmarks, :source => :user

  validates_presence_of :start
  # validates :end, :presence => true

  def create
    self.day_of_week = (start ? start.to_date.wday : nil)
    # initally mark deleted flag as false
    self.deleted = false
    super
  end

  def update
    self.day_of_week = (start ? start.to_date.wday : nil)
    super
  end

  # mark as deleted instead of actually deleting
  def delete
    self.deleted = true
    self.save
  end

  def self.find_with(params)
    user_id = params[:user_id]

    unless(params[:channel_id].to_s.empty?)
      channel = Channel.find(params[:channel_id].to_i)

      params[:option_day] ||= channel.option_day || 0
      params[:start_days] ||= channel.start_days || ""
      params[:end_days] ||= channel.end_days || ""
      params[:start_seconds] ||= channel.start_seconds || ""
      params[:end_seconds] ||= channel.end_seconds || ""
      params[:low_price] ||= channel.low_price || ""
      params[:high_price] ||= channel.high_price || ""
      params[:included_tags] ||= channel.included_tags ? channel.included_tags.split(',') : nil
      params[:excluded_tags] ||= channel.excluded_tags ? channel.excluded_tags.split(',') : nil
      params[:lat_min] ||= ""
      params[:lat_max] ||= ""
      params[:long_min] ||= ""
      params[:long_max] ||= ""
      params[:offset] ||= 0
      params[:search] ||= ""
      params[:sort] ||= channel.sort || 0
      params[:name] ||= channel.name || ""
    end

    if(params[:included_tags] && params[:included_tags].is_a?(String))
      params[:included_tags] = params[:included_tags].split(",")
    end
    
    if(params[:excluded_tags] && params[:excluded_tags].is_a?(String))
      params[:excluded_tags] = params[:excluded_tags].split(",")
    end

    # @tags = Tag.includes(:parentTag, :childTags).all
    # @parentTags = @tags.select{ |tag| tag.parentTag.nil? }

    search_match = occurrence_match = location_match = tag_include_match = tag_exclude_match = low_price_match = high_price_match = "TRUE"

    @amount = 200
    @offset = 0
    bookmarked = !params[:bookmark_type].to_s.empty?
    isCollection = !params[:collection_type].to_s.empty?

    join_clause = ""
    where_clause = "TRUE"

    if(bookmarked)

      if(params[:bookmark_type] == "event")

        join_clause = "INNER JOIN events ON occurrences.event_id = events.id
                       INNER JOIN venues ON events.venue_id = venues.id
                       INNER JOIN bookmarks ON occurrences.id = bookmarks.bookmarked_id"

        where_clause = "bookmarks.user_id = #{user_id} AND bookmarks.bookmarked_type = 'Occurrence'"

      elsif(params[:bookmark_type] == "venue")

        join_clause = "INNER JOIN events ON occurrences.event_id = events.id
                       INNER JOIN venues ON events.venue_id = venues.id
                       INNER JOIN bookmarks ON venues.id = bookmarks.bookmarked_id"

        where_clause = "bookmarks.user_id = #{user_id} AND bookmarks.bookmarked_type = 'Venue'"

      elsif(params[:bookmark_type] == "act")
        
        join_clause = "INNER JOIN events ON occurrences.event_id = events.id
                       INNER JOIN venues ON events.venue_id = venues.id
                       LEFT OUTER JOIN acts_events ON events.id = acts_events.event_id
                       LEFT OUTER JOIN acts ON acts.id = acts_events.act_id
                       INNER JOIN bookmarks ON acts.id = bookmarks.bookmarked_id"

        where_clause = "bookmarks.user_id = #{user_id} AND bookmarks.bookmarked_type = 'Act'"

      end
    elsif(isCollection)

      if(params[:collection_type] == "venue")

        join_clause = "INNER JOIN events ON occurrences.event_id = events.id
                       INNER JOIN venues ON events.venue_id = venues.id"

        where_clause = "venues.id IN (#{params[:collection]})"

      elsif(params[:collection_type] == "act")

        join_clause = "INNER JOIN events ON occurrences.event_id = events.id
                       INNER JOIN venues ON events.venue_id = venues.id
                       LEFT OUTER JOIN acts_events ON events.id = acts_events.event_id
                       LEFT OUTER JOIN acts ON acts.id = acts_events.act_id"

        where_clause = "acts.id IN (#{params[:collection]})"

      end
    else
      # search
      unless(params[:search].to_s.empty?)
        search = params[:search].gsub(/[^0-9a-z ]/i, '').upcase
        searches = search.split(' ')
        
        search_match_arr = []
        searches.each do |word|
          search_match_arr.push("(upper(venues.name) LIKE '%#{word}%' OR upper(events.description) LIKE '%#{word}%' OR upper(events.title) LIKE '%#{word}%')")
        end

        search_match = search_match_arr * " AND "
      end


      # date/time
      start_date_check = "occurrences.start >= '#{Date.today()}'"
      end_date_check = start_time_check = end_time_check = day_check = "TRUE"
      occurrence_start_time = "((EXTRACT(HOUR FROM occurrences.start) * 3600) + (EXTRACT(MINUTE FROM occurrences.start) * 60))"

      event_start_date = event_end_date = nil
      if(!params[:start_date].to_s.empty?)
        event_start_date = Date.parse(params[:start_date])
      else
        event_start_date = Date.today().advance(:days => (params[:start_days].to_s.empty? ? 0 : params[:start_days].to_i))
      end
      if(!params[:end_date].to_s.empty?)
        event_end_date = Date.parse(params[:end_date]).advance(:days => 1)
      else
        event_end_date = Date.today().advance(:days => (params[:end_days].to_s.empty? ? 1 : (params[:end_days].to_i == -1) ? 365000 : params[:end_days].to_i + 1))
      end

      start_date_check = "occurrences.start >= '#{event_start_date}'"
      end_date_check = "occurrences.start <= '#{event_end_date}'"

      unless(params[:start_seconds].to_s.empty? && params[:end_seconds].to_s.empty?)
        event_start_time = params[:start_seconds].to_s.empty? ? 0 : params[:start_seconds].to_i
        event_end_time = params[:end_seconds].to_s.empty? ? 86400 : params[:end_seconds].to_i

        start_time_check = "#{occurrence_start_time} >= #{event_start_time}"
        end_time_check = "#{occurrence_start_time} <= #{event_end_time}"
      end


      unless(params[:day].to_s.empty?)
        event_days = params[:day].collect { |day| day.to_i } * ','

        day_check = "#{event_days ? "occurrences.day_of_week IN (#{event_days})" : "TRUE" }"
      end

      occurrence_match = "#{start_date_check} AND #{end_date_check} AND #{start_time_check} AND #{end_time_check} AND #{day_check}"


      # location
      if(params[:lat_min].to_s.empty? || params[:long_min].to_s.empty? || params[:lat_max].to_s.empty? || params[:long_max].to_s.empty?)
        @ZoomDelta = {
                 11 => { :lat => 0.30250564 / 2, :long => 0.20942688 / 2 }, 
                 13 => { :lat => 0.0756264644 / 2, :long => 0.05235672 / 2 }, 
                 14 => { :lat => 0.037808182 / 2, :long => 0.02617836 / 2 }
                }

        # 30.268093,-97.742808
        @lat = params[:lat_center] || 30.268093
        @long = params[:long_center] || -97.742808
        @zoom = params[:zoom] || 11

        # unless params[:location].to_s.empty?
        #   json_object = JSON.parse(open("http://maps.googleapis.com/maps/api/geocode/json?sensor=false&address=" + URI::encode(params[:location])).read)
        #   unless (json_object.nil? || json_object["results"].length == 0)

        #     @lat = json_object["results"][0]["geometry"]["location"]["lat"]
        #     @long = json_object["results"][0]["geometry"]["location"]["lng"]
        #     # if the results are of a city, keep it zoomed out aways
        #     if (json_object["results"][0]["address_components"][0]["types"].index("locality").nil?)
        #       @zoom = 14
        #     end
        #   end
        # end

        @lat_delta = @ZoomDelta[@zoom][:lat]
        @long_delta = @ZoomDelta[@zoom][:long]
        @lat_min = @lat - @lat_delta
        @lat_max = @lat + @lat_delta
        @long_min = @long - @long_delta
        @long_max = @long + @long_delta
      else
        @lat_min = params[:lat_min]
        @lat_max = params[:lat_max]
        @long_min = params[:long_min]
        @long_max = params[:long_max]
      end

      location_match = "venues.id = events.venue_id AND venues.latitude >= #{@lat_min} AND venues.latitude <= #{@lat_max} AND venues.longitude >= #{@long_min} AND venues.longitude <= #{@long_max}"

      # tags
      unless(params[:included_tags].to_s.empty?)
        tags_mush = params[:included_tags] * ','

        # tag_include_match = "events.id IN (
        #               SELECT event_id 
        #                 FROM events, tags, events_tags 
        #                 WHERE events_tags.event_id = events.id AND events_tags.tag_id = tags.id AND tags.id IN (#{tags_mush}) 
        #                 GROUP BY event_id 
        #                 HAVING COUNT(tag_id) >= #{ params[:included_tags].count }
        #             )"

        tag_include_match = "tags.id IN (#{tags_mush})"
      end

      unless(params[:excluded_tags].to_s.empty?)
        tags_mush = params[:excluded_tags] * ','
        tag_exclude_match = "events.id NOT IN (
                      SELECT event_id 
                        FROM events, tags, events_tags 
                        WHERE events_tags.event_id = events.id AND events_tags.tag_id = tags.id AND tags.id IN (#{tags_mush}) 
                        GROUP BY event_id
                    )"
      end

      # price
      unless(params[:low_price].to_s.empty?)
        low_price = params[:low_price].to_i
        low_price_match = "events.price >= #{low_price}"
      end

      unless(params[:high_price].to_s.empty?)
        high_price = params[:high_price].to_i
        high_price_match = "events.price <= #{high_price}"
      end

      # order_by = "occurrences.start"
      # if(params[:sort].to_s.empty? || params[:sort].to_i == 0)
      #   # order by event score when sorting by popularity
      #   order_by = "CASE events.views 
      #                 WHEN 0 THEN 0
      #                 ELSE (LEAST((events.clicks*1.0)/(events.views),1) + 1.96*1.96/(2*events.views) - 1.96 * SQRT((LEAST((events.clicks*1.0)/(events.views),1)*(1-LEAST((events.clicks*1.0)/(events.views),1))+1.96*1.96/(4*events.views))/events.views))/(1+1.96*1.96/events.views)
      #               END DESC"
      # end

      join_clause = "INNER JOIN events ON occurrences.event_id = events.id
                     INNER JOIN venues ON events.venue_id = venues.id
                     LEFT OUTER JOIN events_tags ON events.id = events_tags.event_id
                     LEFT OUTER JOIN tags ON tags.id = events_tags.tag_id"

      where_clause = "#{search_match} AND #{occurrence_match} AND #{location_match} AND #{tag_include_match} AND #{tag_exclude_match} AND #{low_price_match} AND #{high_price_match}"

    end

    # the big enchilada
    query = "SELECT DISTINCT ON (events.id) occurrences.id AS occurrence_id, events.id AS event_id, venues.id AS venue_id, occurrences.start AS occurrence_start
              FROM occurrences 
                #{join_clause}
              WHERE #{where_clause} AND occurrences.start >= '#{Date.today()}' AND occurrences.deleted IS NOT TRUE
              ORDER BY events.id, occurrences.start"
    
    return ActiveRecord::Base.connection.select_all(query)
  
    # # old queries
    # if(bookmarked)
    #   user_id = params[:user_id]

    #   if(params[:bookmark_type] == "event")
    #     query = "SELECT DISTINCT ON (events.id) occurrences.id AS occurrence_id, events.id AS event_id, venues.id AS venue_id, occurrences.start AS occurrence_start
    #           FROM occurrences 
    #             INNER JOIN events ON occurrences.event_id = events.id
    #             INNER JOIN venues ON events.venue_id = venues.id
    #             INNER JOIN bookmarks ON occurrences.id = bookmarks.bookmarked_id
    #           WHERE bookmarks.user_id = #{user_id} AND bookmarks.bookmarked_type = 'Occurrence'
    #           ORDER BY events.id, occurrences.start"
    #   elsif(params[:bookmark_type] == "venue")
    #     query = "SELECT DISTINCT ON (events.id) occurrences.id AS occurrence_id, events.id AS event_id, venues.id AS venue_id, occurrences.start AS occurrence_start
    #           FROM occurrences 
    #             INNER JOIN events ON occurrences.event_id = events.id
    #             INNER JOIN venues ON events.venue_id = venues.id
    #             INNER JOIN bookmarks ON venues.id = bookmarks.bookmarked_id
    #           WHERE bookmarks.user_id = #{user_id} AND bookmarks.bookmarked_type = 'Venue'
    #           ORDER BY events.id, occurrences.start"
    #   elsif(params[:bookmark_type] == "act")
    #     query = "SELECT DISTINCT ON (events.id) occurrences.id AS occurrence_id, events.id AS event_id, venues.id AS venue_id, occurrences.start AS occurrence_start
    #           FROM occurrences 
    #             INNER JOIN events ON occurrences.event_id = events.id
    #             INNER JOIN venues ON events.venue_id = venues.id
    #             LEFT OUTER JOIN acts_events ON events.id = acts_events.event_id
    #             LEFT OUTER JOIN acts ON acts.id = acts_events.act_id
    #             INNER JOIN bookmarks ON acts.id = bookmarks.bookmarked_id
    #           WHERE bookmarks.user_id = #{user_id} AND bookmarks.bookmarked_type = 'Act'
    #           ORDER BY events.id, occurrences.start"
    #   end
    # elsif(isCollection)
    #   if(params[:collection_type] == "venue")
    #     query = "SELECT DISTINCT ON (events.id) occurrences.id AS occurrence_id, events.id AS event_id, venues.id AS venue_id, occurrences.start AS occurrence_start
    #           FROM occurrences 
    #             INNER JOIN events ON occurrences.event_id = events.id
    #             INNER JOIN venues ON events.venue_id = venues.id
    #           WHERE venues.id IN (#{params[:collection]})
    #           ORDER BY events.id, occurrences.start"
    #   elsif(params[:collection_type] == "act")
    #     query = "SELECT DISTINCT ON (events.id) occurrences.id AS occurrence_id, events.id AS event_id, venues.id AS venue_id, occurrences.start AS occurrence_start
    #           FROM occurrences 
    #             INNER JOIN events ON occurrences.event_id = events.id
    #             INNER JOIN venues ON events.venue_id = venues.id
    #             LEFT OUTER JOIN acts_events ON events.id = acts_events.event_id
    #             LEFT OUTER JOIN acts ON acts.id = acts_events.act_id
    #           WHERE acts.id IN (#{params[:collection]})
    #           ORDER BY events.id, occurrences.start"
    #   end
    # else
    #   query = "SELECT DISTINCT ON (events.id) occurrences.id AS occurrence_id, events.id AS event_id, venues.id AS venue_id, occurrences.start AS occurrence_start
    #           FROM occurrences 
    #             INNER JOIN events ON occurrences.event_id = events.id
    #             INNER JOIN venues ON events.venue_id = venues.id
    #             LEFT OUTER JOIN events_tags ON events.id = events_tags.event_id
    #             LEFT OUTER JOIN tags ON tags.id = events_tags.tag_id
    #           WHERE #{search_match} AND #{occurrence_match} AND #{location_match} AND #{tag_include_match} AND #{tag_exclude_match} AND #{low_price_match} AND #{high_price_match}
    #           ORDER BY events.id, occurrences.start"
    # end
  end

end

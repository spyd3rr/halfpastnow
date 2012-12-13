require 'pp'
require 'open-uri'
require 'json'

# brittle as hell, because these have to change if we change the map size, and also if we change locales from Austin.
class ZoomDelta
  HighLatitude = 0.037808182 / 2
  HighLongitude = 0.02617836 / 2
  MediumLatitude = 0.0756264644 / 2
  MediumLongitude = 0.05235672 / 2
  LowLatitude = 0.30250564 / 2
  LowLongitude = 0.20942688 / 2
end

class EventsController < ApplicationController
helper :content
def splash
  respond_to do |format|
    format.html { render :layout => false }
  end
end


def index
    @tags = Tag.includes(:parentTag, :childTags).all
    @parentTags = @tags.select{ |tag| tag.parentTag.nil? }

    @amount = 20
    unless(params[:amount].to_s.empty?)
      @amount = params[:amount].to_i
    end

    @offset = 0
    unless(params[:offset].to_s.empty?)
      @offset = params[:offset].to_i
    end

    # 30.268093,-97.742808
    @lat = 30.268093
    @long = -97.742808
    @zoom = 11

    params[:lat_center] = @lat
    params[:long_center] = @long
    params[:zoom] = @zoom

    params[:user_id] = current_user ? current_user.id : nil

    @ids = Occurrence.find_with(params)

    @occurrence_ids = @ids.collect { |e| e["occurrence_id"] }.uniq
    @event_ids = @ids.collect { |e| e["event_id"] }.uniq
    @venue_ids = @ids.collect { |e| e["venue_id"] }.uniq

    order_by = "occurrences.start"
    if(params[:sort].to_s.empty? || params[:sort].to_i == 0)
      # order by event score when sorting by popularity
      order_by = "CASE events.views 
                    WHEN 0 THEN 0
                    ELSE (LEAST((events.clicks*1.0)/(events.views),1) + 1.96*1.96/(2*events.views) - 1.96 * SQRT((LEAST((events.clicks*1.0)/(events.views),1)*(1-LEAST((events.clicks*1.0)/(events.views),1))+1.96*1.96/(4*events.views))/events.views))/(1+1.96*1.96/events.views)
                  END DESC"
    end

    @allOccurrences = Occurrence.includes(:event => :tags).find(@occurrence_ids, :order => order_by)
    @occurrences = @allOccurrences.drop(@offset).take(@amount)

    # generating tag list for occurrences

    @occurringTags = {}

    @tagCounts = []

    @parentTags.each do |parentTag|
      @tagCounts[parentTag.id] = {
        :count => 0,
        :children => [],
        :id => parentTag.id,
        :name => parentTag.name,
        :parent => nil
      }
      parentTag.childTags.each do |childTag|
        @tagCounts[childTag.id] = {
          :count => 0,
          :children => [],
          :id => childTag.id,
          :name => childTag.name,
          :parent => @tagCounts[parentTag.id]
        }
        @tagCounts[parentTag.id][:children].push(@tagCounts[childTag.id])
      end
    end

    @allOccurrences.each do |occurrence|
      occurrence.event.tags.each do |tag|
         @tagCounts[tag.id][:count] += 1
      end
    end

    @parentTags.each do |parentTag|
      @tagCounts[parentTag.id][:children] = @tagCounts[parentTag.id][:children].sort_by { |tagCount| tagCount[:count] }.reverse
    end

    @tagCounts = @tagCounts.sort_by { |tagCount| tagCount ? tagCount[:count] : 0 }.compact.reverse

    if @event_ids.size > 0
      ActiveRecord::Base.connection.update("UPDATE events
        SET views = views + 1
        WHERE id IN (#{@event_ids * ','})")

      ActiveRecord::Base.connection.update("UPDATE venues
        SET views = views + 1
        WHERE id IN (#{@venue_ids * ','})")
    end

    respond_to do |format|
      format.html do
        unless (params[:ajax].to_s.empty?)
          # render :partial => "combo", :locals => { :occurrences => @occurrences, :occurringTags => @occurringTags, :parentTags => @parentTags, :offset => @offset }
          render :partial => "combo", :locals => { :occurrences => @occurrences, :tagCounts => @tagCounts, :parentTags => @parentTags, :offset => @offset }
        end
      end
      format.json { render json: @occurrences.to_json(:include => {:event => {:include => [:tags, :venue, :acts] }}) }
    end
    
  end


  def indexMobile

    # @amount = params[:amount] || 20
    # @offset = params[:offset] || 0

    search_match = occurrence_match = location_match = tag_match = price_match = "TRUE"

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

    # occurrence
    event_start = (params[:start].to_s.empty? ? Date.today.to_datetime.to_s : Time.at(params[:start].to_i).to_datetime.to_s)
    event_end = Time.at(params[:end].to_s.empty? ? 32513174400 : params[:end].to_i).to_datetime.to_s
    event_days = params[:day].to_s.empty? ? nil : params[:day]

    occurrence_match = "occurrences.start >= '#{event_start}' AND occurrences.start <= '#{event_end}' AND #{event_days ? "occurrences.day_of_week IN (#{event_days})" : "TRUE" }"
    
    # location
    if(params[:lat_min].to_s.empty? || params[:long_min].to_s.empty? || params[:lat_max].to_s.empty? || params[:long_max].to_s.empty?)
      @ZoomDelta = {
               11 => { :lat => 0.30250564 / 2, :long => 0.20942688 / 2 }, 
               13 => { :lat => 0.0756264644 / 2, :long => 0.05235672 / 2 }, 
               14 => { :lat => 0.037808182 / 2, :long => 0.02617836 / 2 }
              }
      # # 30.268037,-97.742722
      @lat = 30.268093
      @long = -97.742808
      @zoom = 11

      unless params[:location].to_s.empty?
        json_object = JSON.parse(open("http://maps.googleapis.com/maps/api/geocode/json?sensor=false&address=" + URI::encode(params[:location])).read)
        unless (json_object.nil? || json_object["results"].length == 0)

          @lat = json_object["results"][0]["geometry"]["location"]["lat"]
          @long = json_object["results"][0]["geometry"]["location"]["lng"]
          # if the results are of a city, keep it zoomed out aways
          if (json_object["results"][0]["address_components"][0]["types"].index("locality").nil?)
            @zoom = 14
          end
        end
      end

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
    unless(params[:tags].to_s.empty?)
      @tagIDs = params[:tags].split(",").collect { |str| str.to_i }
      tag_match = "events.id IN (
                    SELECT event_id 
                      FROM events, tags, events_tags 
                      WHERE events_tags.event_id = events.id AND events_tags.tag_id = tags.id AND tags.id IN (#{params[:tags]}) 
                      GROUP BY event_id 
                      HAVING COUNT(tag_id) >= #{@tagIDs.size}
                  )"
    end

    # price
    unless(params[:price].to_s.empty?)
      price_match_arr = []
      
      price_ranges = [0,0.01,10,25,50]
      @prices = params[:price].split(",").collect { |str| str.to_i }
      @prices.each do |i|
        price_match_arr.push("events.price >= #{price_ranges[i]} AND #{ (i == price_ranges.length - 1) ? "TRUE" : "events.price < " + price_ranges[i+1].to_s }")
      end
      price_match = price_match_arr * " OR "
      price_match = "(" + price_match + ")"
    end

    # the big enchilada
    @ids = ActiveRecord::Base.connection.select_all("
      SELECT events.id AS event_id, venues.id AS venue_id
        FROM events 
          INNER JOIN occurrences ON events.id = occurrences.event_id
          INNER JOIN venues ON events.venue_id = venues.id
          LEFT OUTER JOIN events_tags ON events.id = events_tags.event_id
          LEFT OUTER JOIN tags ON tags.id = events_tags.tag_id
        WHERE #{search_match} AND #{occurrence_match} AND #{location_match} AND #{tag_match} AND #{price_match}
        ORDER BY occurrences.start")

    @event_ids = @ids.collect { |e| e["event_id"] }.uniq
    @venue_ids = @ids.collect { |e| e["venue_id"] }.uniq

    @events = Event.includes(:tags, :venue, :occurrences, :recurrences).find(@event_ids)

    if(params[:sort].to_s.empty? || params[:sort] == 0)
      @events = @events.sort_by do |event| 
        event.score
      end.reverse
    end

    if @events.count > 0 
      ActiveRecord::Base.connection.update("UPDATE events
        SET views = views + 1
        WHERE id IN (#{@event_ids * ','})")

      ActiveRecord::Base.connection.update("UPDATE venues
        SET views = views + 1
        WHERE id IN (#{@venue_ids * ','})")
    end

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @events.to_json(:include => [:occurrences, :venue, :recurrences, :tags]) }
      format.mobile { render json: @events.to_json(:include => [:occurrences, :venue, :recurrences, :tags]) }
    end

   

  end

  # GET /events/1
  # GET /events/1.json
  def show

    @occurrence = Occurrence.find(params[:id])
    @event = @occurrence.event

    @event.clicks += 1
    @event.save

    if(current_user)
      bookmark = Bookmark.where(:bookmarked_type => 'Occurrence', :bookmarked_id => @occurrence.id, :user_id => current_user.id).first
      @bookmarkId = bookmark.nil? ? nil : bookmark.id 
    else
      @bookmarkId = nil
    end

    @occurrences = []
    @recurrences = []
    @event.occurrences.each do |occ|
      # check if occurrence is instance of a recurrence
      if occ.recurrence_id.nil? && occ.id != @occurrence.id
        @occurrences << occ
      else
        if occ.recurrence && @recurrences.index(occ.recurrence).nil?
          @recurrences << occ.recurrence
        end
      end
    end
    respond_to do |format|
      format.html { render :layout => "mode" }
      format.json { render json: @event.to_json(:include => [:occurrences, :venue]) }
      format.mobile { render json: @event.to_json(:include => [:occurrences, :venue]) }
    end
  end

  def shunt
    respond_to do |format|
      format.html { render :layout => "mode_lite" }
    end
  end

  # GET /events/new
  # GET /events/new.json
  def new
    @event = Event.new
    #@venues = Venue.all
    
    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @event }
    end
  end

  # GET /events/1/edit
  def edit
    @event = Event.find(params[:id])
    #@venues = Venue.all
  end

  # POST /events
  # POST /events.json
  def create
    @event = Event.new(params[:event])
    @occurrence = Occurrence.new(:start => params[:start], :end => params[:end], :event_id => @event.id)
    # puts params[:start]
    # puts params[:end]
    respond_to do |format|
      if @event.save && @occurrence.save
        format.html { redirect_to @event, notice: 'Event was successfully created.' }
        format.json { render json: @event, status: :created, location: @event }
      else
        format.html { render action: "new" }
        format.json { render json: @event.errors, status: :unprocessable_entity }
      end
    end
  end

  # PUT /events/1
  # PUT /events/1.json
  def update

    @event = Event.find(params[:id])

    respond_to do |format|
      if @event.update_attributes(params[:event])
        format.html { redirect_to @event, notice: 'Event was successfully updated.' }
        format.json { head :ok }
      else
        format.html { render action: "edit" }
        format.json { render json: @event.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /events/1
  # DELETE /events/1.json
  def destroy
    @event = Event.find(params[:id])
    @event.destroy

    respond_to do |format|
      format.html { redirect_to events_url }
      format.json { head :ok }
    end
  end

  def upcoming
    puts "upcoming....."
    if params[:range] == "oneweek"
      # @eventsList = Event.find(:all).map(&:nextOccurrence.to_proc).reject {|x| x.nil?}.delete_if { |x| x.start > 1.week.from_now}
      # @eventsList = Event.find(:all, :conditions => ["(start > ?) AND (start < ?)", Time.now, 1.week.from_now])

      eventsQuery = "
        SELECT occurrences.recurrence_id, occurrences.id, events.id AS event_id, events.title, events.completion, events.venue_id, occurrences.start, events.updated_at, events.user_id
        FROM occurrences, events WHERE occurrences.event_id = events.id AND occurrences.deleted = false AND occurrences.recurrence_id IS NULL 
             AND occurrences.start < now() + interval '1 week' AND occurrences.start >= now() 
        UNION 
        SELECT DISTINCT ON (occurrences.recurrence_id) occurrences.recurrence_id, occurrences.id, events.id AS event_id, events.title, events.completion, events.venue_id, occurrences.start, events.updated_at, events.user_id
        FROM occurrences, events WHERE occurrences.event_id = events.id AND occurrences.deleted = false AND occurrences.recurrence_id IS NOT NULL
             AND occurrences.start < now() + interval '1 week' AND occurrences.start >= now()"
      @eventsList = ActiveRecord::Base.connection.select_all(eventsQuery)
    else params[:range] == "twoweeks"
      # @eventsList = Event.find(:all).map(&:nextOccurrence.to_proc).reject {|x| x.nil?}.delete_if { |x| x.start > 2.week.from_now}
      eventsQuery = "
        SELECT occurrences.recurrence_id, occurrences.id, events.id AS event_id, events.title, events.completion, events.venue_id, occurrences.start, events.updated_at, events.user_id
        FROM occurrences, events WHERE occurrences.event_id = events.id AND occurrences.deleted = false AND occurrences.recurrence_id IS NULL 
             AND occurrences.start < now() + interval '2 weeks' AND occurrences.start >= now() 
        UNION 
        SELECT DISTINCT ON (occurrences.recurrence_id) occurrences.recurrence_id, occurrences.id, events.id AS event_id, events.title, events.completion, events.venue_id, occurrences.start, events.updated_at, events.user_id
        FROM occurrences, events WHERE occurrences.event_id = events.id AND occurrences.deleted = false AND occurrences.recurrence_id IS NOT NULL
             AND occurrences.start < now() + interval '2 weeks' AND occurrences.start >= now()"
      @eventsList = ActiveRecord::Base.connection.select_all(eventsQuery)
    end
    @outputList = []

    @eventsList.each do |e|
      unless e["event_id"].nil?
        # @outputList << {'id' => e.id, 'event_id' => e.event.id, 'event_title' => e.event.title,  'event_completedness' => e.event.completedness, 'venue_id' => e.event.venue.id, 'start' => e.start.strftime("%m/%d @ %I:%M %p"), 'owner' => User.where(:id => e.event.user_id).exists? ? User.find(e.event.user_id).fullname : "", 'updated_at' => e.event.updated_at.strftime("%m/%d @ %I:%M %p")}
        @outputList << {'id' => e["id"], 'event_id' => e["event_id"], 'event_title' => e["title"],  'event_completedness' => e["completion"], 'venue_id' => e["venue_id"], 'start' => Time.parse(e["start"]).strftime("%m/%d @ %I:%M %p"), 'owner' => User.where(:id => e["user_id"]).exists? ? User.find(e["user_id"]).fullname : "", 'updated_at' => Time.parse(e["updated_at"]).strftime("%m/%d @ %I:%M %p")}
      end
    end
    respond_to do |format|
      format.json { render json: @outputList }
    end
  end
  
end

require 'pp'

class Price
  FREE = 0
  ONE = 5
  TWO = 10
  THREE = 25
end

class EventsController < ApplicationController
  # GET /events
  # GET /events.json
  def index
    @events = Event.search params[:search]

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @events }
    end
  end

  def fromRaw
    puts params

    if request.post? 
      puts "\n# POST\n"
      if(params["venue-type"] == "existing")
        params[:event].delete("venue_attributes")
      end

      puts params

      params[:event]["occurrences_attributes"]["0"]["day_of_week"] = Date.parse(params[:event]["occurrences_attributes"]["0"]["start(1i)"] + "-" + params[:event]["occurrences_attributes"]["0"]["start(2i)"] + "-" + params[:event]["occurrences_attributes"]["0"]["start(3i)"]).wday
      @event = Event.new(params[:event])
      @event.save
    end

    if params[:delete_id]
      @dRawEvent = RawEvent.find(params[:delete_id])
      if @dRawEvent
        @dRawEvent.deleted = true
        @dRawEvent.save
      end
    end

    #get a random RawEvent from non-submitted/deleted RawEvents
    @rawEvent = RawEvent.first(:order => "RANDOM()", :conditions => "submitted IS NULL AND deleted IS NULL")
    @event = Event.new
    @occurrence = Occurrence.new({
      :start => @rawEvent.start,
      :end => @rawEvent.end
    })
    @venue = Venue.new({
      :name => @rawEvent.venue_name,
      :address => @rawEvent.venue_address,
      :city => @rawEvent.venue_city,
      :state => @rawEvent.venue_state,
      :zip => @rawEvent.venue_zip,
      :latitude => @rawEvent.latitude,
      :longitude => @rawEvent.longitude
    })
    @venueBlank = Venue.new
    
    render :layout => 'venues'

  end

  def find

    #amount, offset, lat_min, lon_min, lat_max, lon_max, price, start, end, [tags]
    params[:amount] = params[:amount] || 10
    params[:offset] = params[:offset] || 0

    @events = Event.search params[:search]

    # find occurrences that start between params[:start] and params[:end] and are on params[:day] day of the week 
    if(params[:start] || params[:end] || params[:day])

      event_start = DateTime.parse(params[:start] || "1900-01-01").to_s
      event_end = DateTime.parse(params[:end] || "9999-12-31").to_s

      event_days = params[:day].split(',')
      
      @occurrences = Occurrence.where("start >= ? AND start <= ? AND day_of_week IN (?)", event_start, event_end, event_days)
      
      # puts @occurrences
      # get events of those occurrences
      @events = @events & @occurrences.collect{ |o| o.event }
    end

    #filter by location
    if(params[:lat_min] && params[:long_min] && params[:lat_max] && params[:long_max])
      @events = @events.find_all {|e| ((params[:lat_min].to_f)..(params[:lat_max].to_f)).include?(e.venue.latitude) && ((params[:long_min].to_f)..(params[:long_max].to_f)).include?(e.venue.longitude) }
    end

    # filter by price/[tags]
    # TODO

    # filter by offset and amount

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @events.to_json(:include => [:occurrences, :venue]) }
    end
  end

  # GET /events/1
  # GET /events/1.json
  def show
    @event = Event.find(params[:id])

    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: @event.to_json(:include => [:occurrences, :venue]) }
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
    puts params[:start]
    puts params[:end]
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
end

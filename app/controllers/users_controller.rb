class UsersController < ApplicationController
  before_filter :authenticate_user!
  # GET /users
  # GET /users.json
  def index

    authorize! :index, @user, :message => 'Not authorized as an administrator.'

    @users = User.all

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @users }
    end
  end

  # GET /users/1
  # GET /users/1.json
  def show

    if params[:id] == nil
      params[:id] = current_user.id
    end
    @user = User.find(params[:id])

    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: @user }
    end
  end

  # GET /users/new
  # GET /users/new.json
  def new
    @user = User.new

    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @user }
    end
  end

  # GET /users/1/edit
  def edit
    @user = User.find(params[:id])
    @user.update_attributes(params[:user])

  end

  # POST /users
  # POST /users.json
  def create
    @user = User.new(params[:user])

    respond_to do |format|
      if @user.save

        format.html { redirect_to @user, notice: 'User was successfully created.' }
        format.json { render json: @user, status: :created, location: @user }
      else
        format.html { render action: "new" }
        format.json { render json: @user.errors, status: :unprocessable_entity }
      end
    end
  end

  # PUT /users/1
  # PUT /users/1.json
  def update
    @user = User.find(params[:id])
    respond_to do |format|
      if @user.update_attributes(params[:user])
        format.html { redirect_to @user, notice: 'User was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render action: "edit" }
        format.json { render json: @user.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /users/1
  # DELETE /users/1.json
  def destroy
    @user = User.find(params[:id])
    @user.destroy

    respond_to do |format|
      format.html { redirect_to users_url }
      format.json { head :no_content }
    end
  end

  def itemslist
    @user = User.find(params[:user_id])
    @itemsList = []

    @user.acts.each do |e|
      unless e.updated_at.nil?
        @itemsList << {'type' => 'Act', 'id' => e.id, 'name' => e.name, 'date' => e.updated_at.strftime("%Y-%m-%d at %I:%M %p")}
      end
    end

    @user.venues.each do |e|
      unless e.updated_at.nil?
        @itemsList << {'type' => 'Venue', 'id' => e.id, 'name' => e.name, 'date' => e.updated_at.strftime("%Y-%m-%d at %I:%M %p")}
      end
    end

    @user.events.each do |e|
      unless e.updated_at.nil?
        @itemsList << {'type' => 'Event', 'id' => (e.nextOccurrence.nil? ? "" : e.nextOccurrence.id), 'venue_id' => e.venue.id, 'name' => e.title, 'date' => e.updated_at.strftime("%Y-%m-%d at %I:%M %p")}
      end
    end
    respond_to do |format|
      format.json { render json: @itemsList }
    end
  end

  def adminStats
    @array = []
    @array << ['User', 'Events', 'Venues', 'Acts']
    @usersList = User.find(:all, :conditions => { :role => [ "admin", "super_admin" ]}, :select => 'id, firstname, lastname')

    case params[:daterange]
      when "24-hours"
        @usersList.each do |u|
          @array << [u.firstname + " " + u.lastname, 
                     Event.find(:all, :conditions => ["(user_id = ?) AND (updated_at > ?)", u.id, 24.hours.ago]).count,
                     Venue.find(:all, :conditions => ["(updated_by = ?) AND (updated_at > ?)", u.id, 24.hours.ago]).count,
                     Act.find(:all, :conditions => ["(updated_by = ?) AND (updated_at > ?)", u.id, 24.hours.ago]).count]
        end
        
      when "yesterday"
        @usersList.each do |u|
          @array << [u.firstname + " " + u.lastname, 
                     Event.find(:all, :conditions => {:user_id => u.id, :updated_at => Date.today-1...Date.today}).count,
                     Venue.find(:all, :conditions => {:updated_by => u.id, :updated_at => Date.today-1...Date.today}).count,
                     Act.find(:all, :conditions => {:updated_by => u.id, :updated_at => Date.today-1...Date.today}).count]
        end

      when "this-week" 
        @usersList.each do |u|
          @array << [u.firstname + " " + u.lastname, 
                     Event.find(:all, :conditions => {:user_id => u.id, :updated_at => Time.now.beginning_of_week...Date.today+1}).count,
                     Venue.find(:all, :conditions => {:updated_by => u.id, :updated_at => Time.now.beginning_of_week...Date.today+1}).count,
                     Act.find(:all, :conditions => {:updated_by => u.id, :updated_at => Time.now.beginning_of_week...Date.today+1}).count]
        end

      when "7-days"
        @usersList.each do |u|
          @array << [u.firstname + " " + u.lastname, 
                     Event.find(:all, :conditions => ["(user_id = ?) AND (updated_at > ?)", u.id, 168.hours.ago]).count,
                     Venue.find(:all, :conditions => ["(updated_by = ?) AND (updated_at > ?)", u.id, 168.hours.ago]).count,
                     Act.find(:all, :conditions => ["(updated_by = ?) AND (updated_at > ?)", u.id, 168.hours.ago]).count]
        end

      when "last-week"
        @usersList.each do |u|
          @array << [u.firstname + " " + u.lastname, 
                     Event.find(:all, :conditions => {:user_id => u.id, :updated_at => Time.now.prev_week...Time.now.beginning_of_week}).count,
                     Venue.find(:all, :conditions => {:updated_by => u.id, :updated_at => Time.now.prev_week...Time.now.beginning_of_week}).count,
                     Act.find(:all, :conditions => {:updated_by => u.id, :updated_at => Time.now.prev_week...Time.now.beginning_of_week}).count]
        end

      when "all-time"
        @usersList.each do |u|
          @array << [u.firstname + " " + u.lastname, 
                     Event.where(:user_id => u.id).count,
                     Venue.where(:updated_by => u.id).count,
                     Act.where(:updated_by => u.id).count]
        end

      else
      end

    respond_to do |format|
      format.json { render json: @array }
    end
  end


end

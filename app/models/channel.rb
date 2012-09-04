class Channel < ActiveRecord::Base
  attr_accessible :day_of_week, :end, :price, :start, :tags, :start_seconds, :end_seconds
  belongs_to :user

  def self.default_channels
  	return Channel.where(:default => true)
  end
end

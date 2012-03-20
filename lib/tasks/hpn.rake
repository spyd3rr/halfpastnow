desc "discard old occurrences and create new ones from recurrences"
task :update_occurrences => :environment do
	puts "update_occurrences"
	old_occurrences = Occurrence.where(:start => (DateTime.new(1900))..(DateTime.now))
	old_occurrences.each do |occurrence|
		puts "occurrence id: " + occurrence.id.to_s
		#if occurrence doesn't have a recurrence, then just destroy it
		#otherwise, try to generate more occurrences from the recurrence.
			#if it can't, and the occurrence is the only occurrence of the recurrence, then destroy the recurrence
		if occurrence.recurrence.nil?
			occurrence.destroy
		else
			if (!occurrence.recurrence.gen_occurrences(1) && occurrence.recurrence.occurrences.count == 1)
				occurrence.recurrence.destroy
			else
				occurrence.destroy
			end
		end
	end
end

desc "generate venues from raw_venues"
task :raw_venues_to_venues => :environment do
	raw_venues = RawVenue.all
	raw_venues.each do |raw_venue| 
		Venue.create({
			:name => raw_venue.name,
	    	:address => raw_venue.address,
	    	:address2 => raw_venue.address2,
	    	:city => raw_venue.city,
	    	:state => raw_venue.state_code,
	    	:zip => raw_venue.zip,
	    	:latitude => raw_venue.latitude,
	    	:longitude => raw_venue.longitude,
	    	:phonenumber => raw_venue.phone
		})
	end
end
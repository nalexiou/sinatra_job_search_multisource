# The primary requirement of a Sinatra application is the sinatra gem.
require 'sinatra'
require 'rubygems'
require 'nokogiri'
require 'open-uri'
require 'net/http'
require 'net/https'
require 'thread'
require 'pony'
require_relative 'httpHandler'
require_relative 'workers'


set :bind, '0.0.0.0'
 
get '/search' do
	erb :form
end

get '/' do
	erb :"index"
end

post '/contact' do
	if params[:name].index(" ") >= 0
		@name = params[:name].split(" ")[0...-1].join(" ")
	else
		@name = params[:name]
	end
  Pony.mail :to => params[:email],
            :from => ENV['MY_TECHNIKALLY_EMAIL'],
            :subject => "Thanks for contacting me, #{@name}!",
            :body => erb(:email)

  Pony.mail :to => ENV['MY_PERSONAL_EMAIL'],
            :from => params[:email],
            :subject => "Website Contact Form, #{params[:name]}!",
            :body => erb(:emailmessage)
            :from => ENV['MY_TECHNIKALLY_EMAIL'],
            :via => :smtp, 
			:via_options => 
				{
				    :address => 'smtp.zoho.com',                     
				    :port => '587',
				    :enable_starttls_auto => true,
				    :user_name => ENV['MY_TECHNIKALLY_EMAIL'],
				    :password => ENV['MY_PASSWORD'],
				    :authentication => :login,
				    :domain => "technikally.com",
				 }

end

post '/search' do
	#GENERATE REGEX BASED ON USER KEYWORDS
	p keywords_array = params[:keywords].scan(/\b(?<=\")[^\"]+(?=\")|[\w]+\b/)
	p keywords_array.map!{|x| x.gsub(/\s+/," ").gsub(/[^\w\s]|_/, "")}
	p keywords_regex = keywords_array.join("|")
	p regex_job_title = /\b(#{keywords_regex})s?\b/i
	# SETUP ARRAYS
	nytmurls =[]
	nojobs = []
	validcompanyurls = []
	careerlinksverified = []
	invalidids = []
	@companies_with_openings = {}

	#GET LAST PAGE OF COMPANIES
	 lastpage = Nokogiri::HTML(getResponse("https://nytm.org/made?list=true").body).at_css("div.digg_pagination > a:nth-last-child(2)").text.to_i

	 (1..lastpage).each do |id|

	  nytmurls << "https://nytm.org/made?list=true&page=#{id}"
	end

	#SET PROC TO GRAB COMPANY LINKS

	grabnynytmhiring = Proc.new do |z|
	  resp = getResponse(z)
	  if resp.code.match(/20\d/)
			Nokogiri::HTML(resp.body).css("a").select{|x| x.text == "Hiring"}.each do |y|
				if y['href'] =~ URI::regexp
				careerlinksverified << y['href']
				end
	       		# puts y['href']
	       	end
	  else
	    # puts "\tNot a valid page; response was: #{resp.code}"
	    invalidids << z
	  end
	end

	#GIVE WORKERS SOME WORK!

	useWorkers(nytmurls, grabnynytmhiring)


techdayurls = []

(10..100).each do |id|
  url = "https://techdayhq.com/events/ny-techday/participants/#{id}"
  techdayurls << url
end  

grabtechdaycompanies = Proc.new do |y|
  resp = getResponse(y)
  begin
	  if resp.code.match(/20\d/)
	  	name = Nokogiri::HTML(resp.body).css('div.company-name').text
	  	p Nokogiri::HTML(resp.body).at_css('a.section-content')['href']
	 	validcompanyurls << Nokogiri::HTML(resp.body).at_css('a.section-content')['href']
	  end
	rescue => e
		p e
	end
end

useWorkers(techdayurls, grabtechdaycompanies)


#Generate array of nystartuphub lists

nystartupurls = []

(1..4).each do |id|
  if id == 1 
  	nystartupurls << "http://nystartuphub.com/list-of-nyc-startups/"
  else
  	nystartupurls << "http://nystartuphub.com/list-of-nyc-startups-#{id}/"
  end
end

cburls = []

grabnyStartupHubSites = Proc.new do |x|
	resp = getResponse(x)
	begin
	  if resp.code.match(/20\d/)
		    Nokogiri::HTML(resp.body).css("div.cbw_subcontent > script").each do |y|
		    	p y['src']
		    	cburls << y['src']
			end
	  else
	    puts "\tNot a valid page; response was: #{resp.code}"
	    invalidids << x
	  end
	rescue => e
		p e
	end
end


useWorkers(nystartupurls, grabnyStartupHubSites)

grabWebsiteCrunchBaseJS = Proc.new do |x|
		begin
        	validcompanyurls << Nokogiri::HTML(getResponse(x).body).css("dd>a").last['href'][2..-3]
        rescue => e
   			p e
  		end
end

useWorkers(cburls, grabWebsiteCrunchBaseJS)


validcompanyurls.uniq!

exclude = %w(flv swf png jpg gif asx zip rar tar 7z gz jar js css dtd xsd ico raw mp3 mp4 wav wmv ape aac ac3 wma aiff mpg mpeg avi mov ogg mkv mka asx asf mp2 m1v m3u f4v pdf doc xls ppt pps bin exe rss xml)			

regex_to_match = /^(job|opening|career)s?|join (our|us)|employment|work here|(we are )?hiring\b/i


grabncareerlinks= Proc.new do |z|
	begin
		resp = getResponse(z)
	if resp.code.match(/(2|3)0\d/)
		Nokogiri::HTML(resp.body).css("a").select{|x| x.text=~ regex_to_match}.each do |y|
		if !y['href'].nil? && !(y['href'] =~ /admission|student|alumni(s)?/i) then
			p absolute_uri = URI.join(z, y['href']).to_s
			careerlinksverified << absolute_uri unless exclude.include?(absolute_uri.split('.').last)
		end
	end
	else
		# puts "\tNot a valid page; response was: #{resp.code}"
		nocareer << url
	end
	rescue Exception => err
		p err
	end
end

useWorkers(validcompanyurls, grabncareerlinks)


	#SAMPLE FILTER CRITERIA
	#regex_job_title = /\b(front ?\-?end|developer|automation|engineer|qa)s?\b/i

	#SET PROC TO LOOK FOR JOBS BASED ON CRITERIA
	grabjobs = Proc.new do |z|
	 begin
	  resp = getResponse(z)	
	  #   s = resp.code
	  # if ! s.valid_encoding?
	  # 	s = s.encode("UTF-16be", :invalid=>:replace, :replace=>"?").encode('UTF-8')
	  # end
	  if resp.code.match(/(2|3)0\d/)
	  	if !Nokogiri::HTML(resp.body).text.match(regex_job_title).nil?
			@companies_with_openings[z] = Nokogiri::HTML(resp.body).text.downcase.scan(regex_job_title)
		else
			nojobs << z
		end

	  else
	    # puts "\tNot a valid page; response was: #{resp.code} for site: #{url}" 
	    nojobs << z
	  end

	  rescue Exception => err
	  # p err
	  # p z
	  end
	 end

	 #GIVE WORKERS SOME MORE WORK!

	 useWorkers(careerlinksverified, grabjobs)
	 @companies_with_openings = @companies_with_openings.sort
	 
	  # this tells sinatra to render the Embedded Ruby template /views/shows.erb
	  erb :shows

end
def getResponse(givenurl, limit = 5)
	raise ArgumentError, 'HTTP redirect too deep' if limit == 0
	begin
	 	url = URI.parse(givenurl)
	 	http = Net::HTTP.new(url.host, url.port)
		http.read_timeout = 10
		http.open_timeout = 8
		http.use_ssl = (url.scheme == 'https')
		resp = http.start() do |http|
			http.get(url.request_uri, 
			{'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/38.0.2125.111 Safari/537.36'}
			)
	end
	case resp
	  when Net::HTTPSuccess     then resp
	  when Net::HTTPRedirection then getResponse(resp['location'], limit - 1)
	  else
	    resp.error!
  	end
  	rescue Exception => e
  	end
end

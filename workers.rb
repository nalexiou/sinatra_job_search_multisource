def useWorkers(urlArray, task)
	begin
	work_q = Queue.new
	urlArray.each{|x| work_q.push x }
	workers = (0...100).map do
	  Thread.new do
	    begin
	      while x = work_q.pop(true)
	      	begin
	      		task.call(x)
	  		end
	      end
	    rescue ThreadError
	    end
	  end
	end
	workers.map(&:join)
	rescue Exception => each
	end
end
require 'sinatra'
require 'sqlite3'
require 'org-ruby'
require 'base64'
require 'yaml'
require 'mimemagic'

conf = YAML.load(File.read('config.yaml'))

set :port, conf['port'] or 4567
img_save = conf['image_location'] or 'public/i'

include FileUtils::Verbose

db = SQLite3::Database.new "kland.db"

# set up the database
db.execute <<-SQL
	create table if not exists threads (
		id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
		title VARCHAR(80) NOT NULL
	);
SQL
db.execute <<-SQL
	create table if not exists images (
		id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
		url VARCHAR(80) UNIQUE NOT NULL,
		bucket VARCHAR(80)
	);
SQL
db.execute <<-SQL
	create table if not exists posts (
		id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
		content TEXT NOT NULL,
		author VARCHAR(80),
		tripcode VARCHAR(80),
		thread_id INTEGER NOT NULL,
		image_id INTEGER,
		timestamp DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL,
		FOREIGN KEY (thread_id) REFERENCES threads(id)
		ON DELETE CASCADE,
		FOREIGN KEY (image_id) REFERENCES images(id)
	);
SQL

def hash_tripcode(tripcode)
	Base64.encode64(Digest::SHA2.new(512).digest(tripcode))[0..9]
end

def format_timestamp(timestamp)
	Time.at(timestamp).strftime("%d/%m/%Y, %I:%M:%S %p")
end

def generate_image_filename()
	(0...5).map { (97 + rand(26)).chr }.join
end

get '/' do
	class ThreadEntry 
		attr_reader :id, :title, :firstPostTimestamp, :lastPostTimestamp, :postCount
		def initialize(id, title, firstPostTimestamp, lastPostTimestamp, postCount)
			@id = id
			@title = title
			@firstPostTimestamp = format_timestamp(firstPostTimestamp)
			@lastPostTimestamp = format_timestamp(lastPostTimestamp)
			@postCount = postCount
		end
	end

	@threads = []

	db.execute("
		SELECT
			t.id,
			t.title, 
			STRFTIME('%s', first.timestamp),
			STRFTIME('%s', last.timestamp),
			COUNT(counting.id) AS postCount
		FROM threads t
			LEFT JOIN posts first
			ON first.id = (
				SELECT id
				FROM posts
				WHERE thread_id = t.id
				ORDER BY id ASC
				LIMIT 1
			)
		  	LEFT JOIN posts last
		  	ON last.id = (
				SELECT id
				FROM posts
				WHERE thread_id = t.id
				ORDER BY id DESC
				LIMIT 1
		  	)
			INNER JOIN posts counting
			ON counting.thread_id = t.id
		GROUP BY t.id
		ORDER BY last.id DESC;
	").each do |id, title, fPostTime, lPostTime, postCount|
		@threads << ThreadEntry.new(id, title, fPostTime.to_i, lPostTime.to_i, 
			postCount)
	end

	erb :threads, :layout => :layout
end

post '/threads' do
	if params[:content] == "" or params[:subject] == ""
		error 400, 'either the content or the subject is empty'
	end

	db.execute("INSERT INTO threads (title) VALUES (?)", [params[:subject]])
	thread_id = db.last_insert_row_id

	content = params[:content]
	author = params[:author]
	tripcode = params[:trip]
	image_id = nil

	if tripcode != ""
		tripcode = hash_tripcode(tripcode)
	end

	if params[:file] && (tmpfile = params[:file][:tempfile])
		found_filename = false
		filename = ""
		while found_filename == false
			filename = generate_image_filename()
			found_filename = !File.exist?("#{img_save}/#{filename}")
		end
		db.execute("INSERT INTO images (url) VALUES (?)", ['/i/' + filename])

		cp(tmpfile.path, "#{img_save}/#{filename}")
		image_id = db.last_insert_row_id
	end

	db.execute(
		"INSERT INTO posts (content, author, tripcode, thread_id, image_id) VALUES (?, ?, ?, ?, ?)", 
		[content, author, tripcode, thread_id, image_id]
	)

	redirect "/threads/#{thread_id}"
end

get '/threads/:id' do
	class PostEntry 
		attr_reader :id, :content, :author, :tripcode, :timestamp, :img

		def initialize(id, content, author, tripcode, timestamp, img)
			@id = id
			@content = Orgmode::Parser.new(content).to_html
			@author = author
			@tripcode = tripcode
			@timestamp = format_timestamp(timestamp)
			@img = img
		end
	end

	class ThreadEntry
		attr_reader :id, :title

		def initialize(id, title)
			@id = id
			@title = title
		end
	end

	@showNav = true

	thread_row = db.execute("SELECT title FROM threads WHERE id = ?", [params[:id]]).first

	# if the thread doesn't exist, show a 404
	if thread_row == nil
		@header = "Thread not found."
		erb :empty, :layout => :layout
	else
		@thread = ThreadEntry.new(params[:id], thread_row[0])

		@posts = []

		db.execute("
			SELECT p.id, p.content, p.author, p.tripcode, 
			STRFTIME('%s', p.timestamp), i.url
			FROM posts p
			LEFT JOIN images i
			ON i.id = p.image_id
			WHERE p.thread_id = ?
			ORDER BY p.id ASC;
		", [params[:id]]).each do |id, content, author, tripcode, timestamp, img|
			@posts << PostEntry.new(id, content, author, tripcode, timestamp.to_i, img)
		end

		@header = @thread.title

		erb :thread, :layout => :layout
	end
end

post "/threads/:id" do
	if params[:content] == ""
		error 400, 'the content is empty'
	end

	thread_id = params[:id]
	thread_row = db.execute("SELECT title FROM threads WHERE id = ?", [thread_id]).first

	@showNav = true

	if thread_row == nil
		@header = "Thread not found."
		erb :empty, :layout => :layout
	else
		content = params[:content]
		author = params[:author]
		tripcode = params[:trip]
		image_id = nil

		if tripcode != ""
			tripcode = hash_tripcode(tripcode)
		end

		if params[:file] && (tmpfile = params[:file][:tempfile])
			found_filename = false
			filename = ""
			while found_filename == false
				filename = generate_image_filename()
				found_filename = !File.exist?("#{img_save}/#{filename}")
			end
			db.execute("INSERT INTO images (url) VALUES (?)", ['/i/' + filename])

			cp(tmpfile.path, "#{img_save}/#{filename}")
			image_id = db.last_insert_row_id
		end

		db.execute(
			"INSERT INTO posts (content, author, tripcode, thread_id, image_id) VALUES (?, ?, ?, ?, ?)", 
			[content, author, tripcode, thread_id, image_id]
		)
		post_id = db.last_insert_row_id

		redirect "/threads/#{thread_id}#p#{post_id}"
	end
end

get "/images" do
	@ipp = 20
	@page = params[:page] ? params[:page].to_i : 1

	if request.cookies["ipp"] != nil
		@ipp = Base64.decode64(request.cookies["ipp"]).to_i
	end

	@images = []

	if params[:bucket] != nil and params[:bucket] != ""
		@bucket = params[:bucket]
		db.execute("
			SELECT url
			FROM images
			WHERE bucket = ?
			ORDER BY id DESC
			LIMIT ? OFFSET ?;
		", @bucket, @ipp, @ipp * (@page - 1)).each do |url|
			@images << url.first
		end
	else
		db.execute("
			SELECT url
			FROM images
			WHERE bucket IS NULL
			ORDER BY id DESC
			LIMIT ? OFFSET ?;
		", @ipp, @ipp * (@page - 1)).each do |url|
			@images << url.first
		end
	end

	erb :images, :layout => :images
end

post '/uploadimage' do
	bucket = params[:bucket]
	if params[:file] && (tmpfile = params[:file][:tempfile])
		found_filename = false
		filename = ""
		while found_filename == false
			filename = generate_image_filename()
			found_filename = !File.exist?("#{img_save}/#{filename}")
		end
		if bucket != nil and bucket != ""
			bucket = params[:bucket]
			db.execute("INSERT INTO images (url, bucket) VALUES (?, ?)", ['/i/' + filename, bucket])
		else
			db.execute("INSERT INTO images (url) VALUES (?)", ['/i/' + filename])
		end

		cp(tmpfile.path, "#{img_save}/#{filename}")
	end

	if bucket != nil and bucket != ""
		redirect '/images?bucket='+bucket
	else
		redirect '/images'
	end
end

get "/i/:image" do
	image = params[:image]
	filepath = File.join(img_save, image)
	if File.exist?(filepath)
		mime_type = MimeMagic.by_magic(File.open(filepath))
		send_file filepath, type: mime_type
	else
		error 404, "Image not found."
	end
end

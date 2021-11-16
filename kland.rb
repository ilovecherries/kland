require 'sinatra'
require 'sqlite3'
require 'org-ruby'
require 'base64'
require 'yaml'
require 'mimemagic'

conf = YAML.load(File.read('config.yaml'))

set :port, conf['port'] or 4567
$img_save = conf['image_location'] or 'i'

include FileUtils::Verbose

db = SQLite3::Database.new conf['database_location'] or './kland.db'

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

def nil_squeeze(s)
	(s == "") ? nil : s
end

class SQLite3::Database
	def upload_image(path, bucket = nil)
		filename = ''

		loop do
			filename = generate_image_filename()
			if self.execute("SELECT id FROM images WHERE url = ?", ['/i/' + filename]).empty?
				break
			end
		end
		bucket = nil if bucket == ''
		self.execute("INSERT INTO images (url, bucket) VALUES (?, ?)", ['/i/' + filename, bucket])

		cp(path, "#{$img_save}/#{filename}")
		self.last_insert_row_id
	end

	def create_post(thread_id, content, author = nil, tripcode = nil, image = nil)
		if tripcode != nil
			tripcode = hash_tripcode(tripcode)
		end

		if image != nil
			image = self.upload_image(image)
		end

		if author.is_a?(String) 
			author = author.nil_squeeze 
		end

		self.execute(
			"INSERT INTO posts (content, author, tripcode, thread_id, image_id) VALUES (?, ?, ?, ?, ?)", 
			[content, author, tripcode, thread_id, image]
		)
		self.last_insert_row_id
	end

	def create_thread(subject, content, author = nil, tripcode = nil, image = nil)
		self.execute("INSERT INTO threads (title) VALUES (?)", [subject])

		thread_id = self.last_insert_row_id

		create_post(thread_id, content, author, tripcode, image)

		thread_id
	end
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
	subject = params[:subject]
	content = params[:content]

	if content.empty? or subject.empty?
		error 400, 'either the content or the subject is empty'
	end

	author = nil_squeeze(params[:author])
	tripcode = nil_squeeze(params[:tripcode])
	image = if params[:file]
		params[:file][:tempfile].path
	else
		nil
	end

	thread_id = db.create_thread(subject, content, author, tripcode, image)

	redirect "/threads/#{thread_id}"
end

# THREADLINK_REGEX = />>>([0-9]+)/
BACKLINK_REGEX = />>([0-9]+)/

get '/threads/:id' do
	class PostEntry 
		@@backlinks = Hash.new

		attr_reader :id, :content, :author, :tripcode, :timestamp, :img, :backlinks

		def initialize(id, content, author, tripcode, timestamp, img)
			@id = id
			# add thread links before parsing the backlinks
			# content = content.gsub('[[/threads/\1][>>>\0]]')
			# grab the backlinks from the content and then add them to the
			# hashmap
			links = content.match(BACKLINK_REGEX) { |m| m.captures }
			if links
				links.each do |link|
					if @@backlinks[link.to_i].nil?
						@@backlinks[link.to_i] = []
					end
					@@backlinks[link.to_i] << id.to_i
				end
			end
			content= content.gsub(BACKLINK_REGEX, '[[#p\1][\0]]')
			@content = Orgmode::Parser.new(content).to_html
			@author = author
			@tripcode = tripcode
			@timestamp = format_timestamp(timestamp)
			@img = img
			@backlinks = @@backlinks[id.to_i]
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
			ORDER BY p.id DESC;
		", [params[:id]]).each do |id, content, author, tripcode, timestamp, img|
			@posts.unshift(PostEntry.new(id, content, author, tripcode, timestamp.to_i, img))
		end

		@header = @thread.title

		erb :thread, :layout => :layout
	end
end

post "/threads/:id" do
	content = params[:content]

	if content.empty?
		error 400, 'the content is empty'
	end

	author = nil_squeeze(params[:author])
	tripcode = nil_squeeze(params[:tripcode])
	image = if params[:file]
		params[:file][:tempfile]
	else
		nil
	end

	thread_id = params[:id]
	thread_row = db.execute("SELECT title FROM threads WHERE id = ?", [thread_id]).first

	@showNav = true

	if thread_row == nil
		@header = "Thread not found."
		erb :empty, :layout => :layout
	else
		post_id = db.create_post(thread_id, content, author, tripcode, image)

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

	image = if params[:file] && (tmpfile = params[:file][:tempfile])
		tmpfile.path
	else
		nil
	end

	if image.nil?
		error 400, "Image data is empty."
	else
		db.upload_image(image, bucket)

		if bucket != nil and bucket != ""
			redirect '/images?bucket='+bucket
		else
			redirect '/images'
		end
	end
end

get "/i/:image" do
	image = params[:image]
	filepath = File.join($img_save, image)
	if File.exist?(filepath)
		mime_type = MimeMagic.by_magic(File.open(filepath))
		send_file filepath, type: mime_type
	else
		error 404, "Image not found."
	end
end

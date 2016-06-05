require 'sinatra'
require 'haml'
require 'prawn'
require 'aws-sdk'
require 'pony'
require 'sendmail'

get '/' do
  haml :home
end

post '/upload' do
  puts "/upload"
  tempfile = params[:file][:tempfile]
  filename = params[:file][:filename]
  puts tempfile.path
  
  upload(tempfile.path, filename)
  redirect "/list"
end

get '/sqs' do
  sqs = Aws::SQS::Client.new(region: 'eu-central-1')
  poller = Aws::SQS::QueuePoller.new('https://sqs.eu-central-1.amazonaws.com/881078108084/zajac-album', client: sqs)
  poller.poll do |msg|
    puts '----'
    puts msg.body
  end
end

get '/list' do
  @files = get_bucket.objects.collect(&:key)
  haml :list
end

post '/save' do
  result = ""
  email = params[:email]
  
  if params[:file_name].include? ".pdf"
    name = params[:file_name]
  else
    name = params[:file_name] + ".pdf"
  end
  
  FileUtils.mkdir_p 'files' # temporary directory
  
  s3_client = Aws::S3::Client.new(region: 'eu-central-1')
  params[:files].each do |filename|
    # save every choosed files to files/ directory
    s3_client.get_object(
      bucket: '166543-robson', 
      key: filename, 
      response_target: "files/" + filename)
  end

  pdf = Prawn::Document.new
  params[:files].each do |f|
    title = "files/" + f # path to file
    pdf.image title, :at => [50, 250], :width => 300, :height => 350
    pdf.start_new_page
  end

  pdf.render_file "files/" + name # save pdf to file
  
  # send mail
  mail_subject = "Your album: #{name}"
  Pony.mail(
    :to => email, 
    :from => 'fake@wpc2016.uek.krakow.pl', 
    :subject => mail_subject, 
    :body => 'Check attachments.',
    :attachments => {"#{name}" => File.read("files/" + name) })
    
  # delete files from bucket, remove temporary dir
  FileUtils.remove_dir "files";
  params[:files].each do |f|
    obj = get_bucket.object(f)
    obj.delete
  end

  result
end

def get_bucket
  Aws::S3::Resource.new(region: 'eu-central-1').bucket('166543-robson')
end

def upload(file, filename)
  obj = get_bucket.object(filename.downcase)

  if obj.upload_file(file)
    puts "Uploaded #{file}}"
  else
    puts "Could not upload #{file}!"
  end
end
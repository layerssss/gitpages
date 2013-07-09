express = require 'express'
path = require 'path'
fs = require 'fs'
mkdirp = require 'mkdirp'
gravatar = require 'gravatar'
moment = require 'moment'
gitstat = require 'node-gitstat'
{
  exec
} = require 'child_process'

module.exports = app = new express()
heads = {}
checkingout = {}

moment.lang 'zh-cn'
app.locals.moment = moment
app.locals.gravatar = gravatar
app.use (rq, rs, cb)->
  return cb() unless rq.method == 'GET'
  segs = rq.url.split('/').filter (seg)->seg
  return cb() unless segs.length >= 2
  [
    account
    repo
    branch
  ] = segs
  rs.locals.userUsername = account
  rs.locals.repoName = repo
  gitPath = path.join process.env.REPOSITORIES, account, "#{repo}.git"
  
  await fs.exists gitPath, defer exists
  if !exists
    gitPath = path.join process.env.REPOSITORIES, account, "#{repo}/.git"
    await fs.exists gitPath, defer exists
  return cb() unless exists
  rq.gitPath = gitPath
  
  return cb() unless segs.length >= 3
  workingPath = path.join __dirname, 'working', account, repo, branch
  rq.workingPath = workingPath

  while checkingout["#{account}/#{repo}/#{branch}"]
    await setTimeout defer(), 300
  checkingout["#{account}/#{repo}/#{branch}"] = true
  await sync gitPath, branch, workingPath, defer e, rq.repo
  console.log e if e
  checkingout["#{account}/#{repo}/#{branch}"] = false
  cb()

app.use express.static path.join __dirname, 'public'
app.use express.static (path.join __dirname, 'working'),
  index: 'default.html'
app.use '/cdnjs', express.static (path.join __dirname, 'cdnjs', 'ajax', 'libs'),
  index: 'README.txt'
app.use '/cdnjs', express.directory (path.join __dirname, 'cdnjs', 'ajax', 'libs'),
  icons: true
app.use app.router
app.use express.directory (path.join __dirname, 'working'),
  icons: true

app.set 'view engine', 'jade'
app.set 'views', path.join __dirname

sync = (gitPath, branch, workingPath, cb)->
  repo = null
  await getRepo (path.join workingPath, '.git'), branch, defer e, localRepo
  await getRepo gitPath, branch, defer e, repo
  return cb e, repo if e
  unless localRepo? && localRepo.head == repo.head
    await exec "rm -Rf #{workingPath}", defer e
    return cb e, repo if e
    await mkdirp workingPath, defer e
    return cb e, repo if e
    await exec "git clone --depth 1 --branch #{branch} --recursive #{gitPath} #{workingPath}", defer e
    return cb e, repo if e
    opt = 
      cwd: workingPath
      env: {}
    opt.env[k] = v for k, v of process.env
    opt.env.PATH = "#{path.join __dirname, 'node_modules', '.bin'}:#{opt.env.PATH}"
    await exec "make", opt, defer e
    return cb e, repo if e
  cb null, repo

getRepo = (gitPath, branch, cb)->
  repo = 
    gitPath: gitPath
  git = new gitstat gitPath
  await git.log branch, defer e, logs
  return cb e if e
  repo.head = logs[0].hash
  repo.time = moment logs[0].date.trim()
  [
    dummy
    repo.headAuthorName
    repo.headAuthorEmail
  ] = logs[0].author.match /(.*)\s+\<(.*)\>/
  cb null, repo

getUser = (userPath, cb)->
  user = 
    userPath: userPath
    repos: []
    _emailCount: 0
    email: null
    name: null
    emails: {}
  await fs.readdir userPath, defer e, files
  return cb e if e
  for file in files
    continue if file.match /^\./
    await fs.stat (path.join userPath, file), defer e, stats
    return cb e if e
    continue unless stats.isDirectory()
    if file.match /\.git$/
      await getRepo (path.join userPath, file), 'master', defer e, repo
      continue if e
    else
      await getRepo (path.join userPath, file, '.git'), 'master', defer e, repo
      continue if e
    repo.name = file.replace /\.git$/, ''
    user.repos.push repo
    user.emails[repo.headAuthorEmail]?=
      name: repo.headAuthorName
      count: 0
    user.emails[repo.headAuthorEmail].count++
  for email, author of user.emails
    if author.count > user._emailCount
      user._emailCount = author.count
      user.name = author.name
      user.email = email
  cb null, user


app.get '/', (rq, rs, cb)->
  await fs.readdir process.env.REPOSITORIES, defer e, users
  return cb e if e
  rs.locals.repos = []
  for username in users
    await getUser (path.join process.env.REPOSITORIES, username), defer e, user
    continue if e
    if user.repos.length
      user.username = username
      for repo in user.repos
        repo.user = user
        rs.locals.repos.push repo
  rs.locals.repos.sort (r1, r2)-> r2.time - r1.time
  rs.render 'dashboard'

app.get '/:account/:repo/*', (rq, rs, cb)->
  return cb() unless rq.gitPath
  await getRepo rq.gitPath, 'master', defer e, rs.locals.repo
  return cb e if e
  await exec "git --git-dir \"#{rq.gitPath}\" branch", defer e, out, err
  return cb e if e
  branches = out.split('\n').map((b)->b.replace(/\*/, '').trim()).filter((b)->b.length)
  rs.locals.branches = []
  for branch in branches
    await getRepo rq.gitPath, branch, defer e, repo
    return cb e if e
    repo.name = branch
    rs.locals.branches.push repo
  cb()

app.get '/:account/:repo/', (rq, rs, cb)->
  rs.render 'repo'

app.get '/:account/:repo/:branch/', (rq, rs, cb)->
  {
    account
    repo
    branch
  } = rq.params
  workingPath = path.join __dirname, 'working', account, repo, branch
  await fs.readdir workingPath, defer e, files
  return cb e if e
  rs.locals.pages = files.filter (file)-> file.match /^[^\.].*\.html$/
  return cb() unless rs.locals.pages.length
  rs.locals.branchName = branch
  rs.render 'branch'



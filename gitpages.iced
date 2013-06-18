express = require 'express'
path = require 'path'
fs = require 'fs'
git = require "nodegit"
mkdirp = require 'mkdirp'
{
	exec
} = require 'child_process'

module.exports = app = new express()
heads = {}

app.use (req, res, cb)->
	return cb() unless req.method == 'GET'
	segs = req.url.split '/'
	return cb() unless segs.length >= 3
	[
		dummy
		account
		repo
	] = segs
	await fs.exists (path.join process.env.REPOSITORIES, account, "#{repo}.git"), defer exists
	return cb() unless exists
	while heads["#{account}/#{repo}"] == 'checkingout'
		await setTimeout defer(), 300

	await git.repo (path.join process.env.REPOSITORIES, account, "#{repo}.git"), defer e, gitRepo
	return cb e if e
	await gitRepo.branch 'master', defer e, girBranch
	return cb e if e
	await girBranch.sha defer e, gitHead
	return cb e if e

	if heads["#{account}/#{repo}"] != gitHead
		heads["#{account}/#{repo}"] = 'checkingout'

		await mkdirp (path.join __dirname, 'working', account, repo), defer e
		return cb e if e

		await exec "rm -Rf #{path.join __dirname, 'working', account, repo}", defer e
		return cb e if e


		await exec "git clone #{path.join process.env.REPOSITORIES, account, repo}.git #{path.join __dirname, 'working', account, repo}", defer e
		return cb e if e

		opt = 
			cwd: path.join __dirname, 'working', account, repo
			env: {}
		opt.env[k] = v for k, v of process.env
		opt.env.PATH = "#{path.join __dirname, 'node_modules', '.bin'}:#{opt.env.PATH}"
		await exec "make", opt, defer e
		console.log e.message if e


		heads["#{account}/#{repo}"] = gitHead
	cb()

app.use express.static path.join __dirname, 'working'

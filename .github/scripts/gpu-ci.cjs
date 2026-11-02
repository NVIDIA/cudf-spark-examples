// Copyright (c) 2026, NVIDIA CORPORATION.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

const catalog = require('../gpu-ci-suites.json');
const workflow = '.github/workflows/gpu-ci.yml';
const gateName = 'GPU CI gate';

function selectSuites(files, config = catalog) {
  if (!Array.isArray(files) || files.some(file =>
    typeof file.filename !== 'string' || !file.filename ||
    (file.previous_filename !== undefined && typeof file.previous_filename !== 'string'))) {
    throw new Error('Invalid PR file metadata');
  }
  const validPaths = paths => Array.isArray(paths) && paths.length > 0 &&
    paths.every(path => typeof path === 'string' && path.length > 0 &&
      !path.startsWith('/') && !path.includes('..') && !/[?*\\]/.test(path));
  if (!validPaths(config.shared_paths) || !config.suites ||
      Object.keys(config.suites).length === 0) {
    throw new Error('Invalid GPU suite catalog');
  }
  const changed = files.flatMap(file => [file.filename, file.previous_filename].filter(Boolean));
  const matches = paths => paths.some(path => changed.some(file =>
    path.endsWith('/') ? file.startsWith(path) : file === path));
  return Object.entries(config.suites).filter(([name, suite]) => {
    if (!/^[a-z][a-z0-9-]*$/.test(name) || !validPaths(suite.paths) ||
        !Array.isArray(suite.jobs) || suite.jobs.length === 0 ||
        suite.jobs.some(job => typeof job !== 'string' || !job.trim()) ||
        new Set(suite.jobs).size !== suite.jobs.length) {
      throw new Error(`Invalid GPU suite: ${name}`);
    }
    return matches(config.shared_paths) || matches(suite.paths);
  }).map(([name]) => name);
}

function pullNumber(context) {
  if (context.eventName === 'pull_request_target') return context.payload.pull_request.number;
  const branch = context.eventName === 'workflow_run' ?
    context.payload.workflow_run.head_branch : context.ref.replace('refs/heads/', '');
  const match = /^pull-request\/([1-9][0-9]*)$/.exec(branch || '');
  if (!match) throw new Error('GPU CI requires an approved pull-request/<number> branch');
  return Number(match[1]);
}

async function changedSuites(github, repo, pr) {
  const files = await github.paginate(github.rest.pulls.listFiles, {
    ...repo, pull_number: pr.number, per_page: 100,
  });
  // GitHub caps this endpoint at 3,000 files. Incomplete detection must not skip tests.
  if (files.length !== pr.changed_files) throw new Error('Incomplete PR file list');
  const suites = selectSuites(files);
  await assertCurrent(github, repo, pr);
  return suites;
}

async function assertCurrent(github, repo, pr) {
  const {data: current} = await github.rest.pulls.get({...repo, pull_number: pr.number});
  if (current.state !== 'open' || current.head.sha !== pr.head.sha ||
      current.base.sha !== pr.base.sha) {
    throw new Error('PR changed during evaluation; rerun GPU CI requirement assessment');
  }
}

async function select({github, context, core}) {
  const {data: pr} = await github.rest.pulls.get({
    ...context.repo, pull_number: pullNumber(context),
  });
  if (context.sha !== pr.head.sha) throw new Error('Approved source is no longer the PR head');
  const suites = await changedSuites(github, context.repo, pr);
  core.setOutput('suites', JSON.stringify(suites));
  await core.summary.addHeading('GPU test selection')
    .addRaw(`PR #${pr.number}, head ${pr.head.sha}: ${suites.join(', ') || 'no affected suites'}`)
    .write();
}

function resultForJobs(run, jobs, suites, config = catalog) {
  if (run.status !== 'completed') {
    return {state: 'pending', description: `GPU CI ${run.status}; required: ${suites.join(', ')}`};
  }
  if (run.conclusion !== 'success') {
    return {state: 'failure', description: `GPU CI ${run.conclusion}; required: ${suites.join(', ')}`};
  }
  if (!Number.isInteger(run.run_attempt) || run.run_attempt < 1 || jobs.some(job =>
    !Number.isInteger(job.run_attempt) || job.run_attempt < 1 || job.run_attempt > run.run_attempt)) {
    throw new Error('Inconsistent GPU CI attempt metadata');
  }
  const required = ['Select GPU test suites', ...suites.flatMap(name => config.suites[name].jobs)];
  const missing = required.filter(name => {
    const matches = jobs.filter(job => job.name === name);
    // Rerun-failed-jobs retains successful producers from earlier attempts of this same run/SHA.
    const attempt = Math.max(...matches.map(job => job.run_attempt));
    const latest = matches.filter(job => job.run_attempt === attempt);
    return latest.length !== 1 || latest[0].status !== 'completed' ||
      latest[0].conclusion !== 'success';
  });
  return missing.length ?
    {state: 'failure', description: `Required jobs did not pass: ${missing.join(', ')}`} :
    {state: 'success', description: `Required GPU suites passed: ${suites.join(', ')}`};
}

async function assessRun(github, repo, candidate, suites, core) {
  // A rerun can start between the run and jobs reads. Retry metadata, never GPU work.
  const request = {...repo, run_id: candidate.id};
  for (let observation = 1; observation <= 3; observation++) {
    const {data: run} = await github.rest.actions.getWorkflowRun(request);
    // The lifecycle event may already know about an attempt/completion absent from REST reads.
    const caughtUp = run.run_attempt >= candidate.run_attempt &&
      !(run.run_attempt === candidate.run_attempt && candidate.status === 'completed' &&
        (run.status !== 'completed' || run.conclusion !== candidate.conclusion));
    if (caughtUp) {
      if (run.status !== 'completed') return resultForJobs(run, [], suites);
      const jobs = await github.paginate(github.rest.actions.listJobsForWorkflowRun,
        {...request, filter: 'all', per_page: 100});
      const {data: latest} = await github.rest.actions.getWorkflowRun(request);
      if (run.run_attempt === latest.run_attempt && run.status === latest.status &&
          run.conclusion === latest.conclusion &&
          !jobs.some(job => job.run_attempt > run.run_attempt)) {
        return resultForJobs(run, jobs, suites);
      }
    }
    core.info(`GPU CI run ${run.id}: metadata not stable at observation ${observation}/3; ` +
      `expected at least ${candidate.run_attempt}/${candidate.status}, ` +
      `observed ${run.run_attempt}/${run.status}`);
    if (observation < 3) await new Promise(resolve => setTimeout(resolve, 2000));
  }
  throw new Error('GPU CI run/job metadata did not stabilize; rerun the requirement assessment');
}

async function assess({github, context, core}) {
  const repo = context.repo;
  const {data: pr} = await github.rest.pulls.get({...repo, pull_number: pullNumber(context)});
  // Status contexts are shared by SHA: do not let another target branch waive main's gate.
  if (pr.state !== 'open' || pr.base.ref !== 'main') return;
  const assessmentUrl = `${context.serverUrl}/${repo.owner}/${repo.repo}/actions/runs/${context.runId}`;
  const publish = (state, description, targetUrl = assessmentUrl) =>
    github.rest.repos.createCommitStatus({
      ...repo, sha: pr.head.sha, context: gateName, state,
      description: description.slice(0, 140), target_url: targetUrl,
    });

  // Publish on the PR head, not pull_request_target/workflow_run's default-branch SHA.
  await publish('pending', 'Checking which GPU suites are required');
  try {
    const suites = await changedSuites(github, repo, pr);
    let result = {state: 'success', description: 'No affected GPU test suites'};
    let targetUrl = assessmentUrl;
    if (suites.length) {
      const {data} = await github.rest.actions.listWorkflowRuns({
        ...repo, workflow_id: 'gpu-ci.yml', event: 'push',
        branch: `pull-request/${pr.number}`, head_sha: pr.head.sha, per_page: 100,
      });
      const candidates = context.eventName === 'workflow_run' ?
        [context.payload.workflow_run, ...data.workflow_runs] : data.workflow_runs;
      const run = candidates.filter(candidate =>
        candidate.path === workflow && candidate.event === 'push' &&
        candidate.head_sha === pr.head.sha && candidate.head_branch === `pull-request/${pr.number}` &&
        candidate.head_repository?.full_name === `${repo.owner}/${repo.repo}` &&
        candidate.actor?.login === 'copy-pr-bot[bot]'
      ).sort((a, b) => b.id - a.id || b.run_attempt - a.run_attempt ||
        Number(b.status === 'completed') - Number(a.status === 'completed'))[0];
      if (!run) {
        result = {state: 'pending', description: 'GPU tests required; awaiting /ok to test for this head'};
      } else {
        targetUrl = run.html_url;
        result = await assessRun(github, repo, run, suites, core);
      }
    }
    await assertCurrent(github, repo, pr);
    await publish(result.state, result.description, targetUrl);
    core.info(`${gateName}: ${result.state}: ${result.description}`);
    await core.summary.addHeading(gateName)
      .addRaw(`PR #${pr.number}, head ${pr.head.sha}\n\n${result.description}\n\n${targetUrl}`)
      .write();
  } catch (error) {
    await publish('error', 'Unable to verify GPU CI requirements; see assessment logs');
    throw error;
  }
}

module.exports = {select, assess, selectSuites, resultForJobs};

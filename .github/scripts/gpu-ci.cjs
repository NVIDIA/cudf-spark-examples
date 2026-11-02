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
        suite.jobs.some(job => typeof job !== 'string' || !/^[a-zA-Z_][a-zA-Z0-9_-]*$/.test(job)) ||
        new Set(suite.jobs).size !== suite.jobs.length) {
      throw new Error(`Invalid GPU suite: ${name}`);
    }
    return matches(config.shared_paths) || matches(suite.paths);
  }).map(([name]) => name);
}

function pullNumber(context) {
  const match = context.eventName === 'push' &&
    /^refs\/heads\/pull-request\/([1-9][0-9]*)$/.exec(context.ref || '');
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
      current.base.sha !== pr.base.sha || current.base.ref !== pr.base.ref) {
    throw new Error('PR changed during suite selection; approve and run the current PR head');
  }
}

async function select({github, context, core}) {
  const {data: pr} = await github.rest.pulls.get({
    ...context.repo, pull_number: pullNumber(context),
  });
  // Check runs share a head SHA; another target branch must not waive main's GPU tests.
  if (pr.base.ref !== 'main') throw new Error('GPU CI gate only supports PRs targeting main');
  if (context.sha !== pr.head.sha) throw new Error('Approved source is no longer the PR head');
  const suites = await changedSuites(github, context.repo, pr);
  core.setOutput('suites', JSON.stringify(suites));
  core.setOutput('required-jobs', JSON.stringify([
    ...new Set(['select', ...suites.flatMap(name => catalog.suites[name].jobs)]),
  ]));
  await core.summary.addHeading('GPU test selection')
    .addRaw(`PR #${pr.number}, head ${pr.head.sha}: ${suites.join(', ') || 'no affected suites'}`)
    .write();
}

module.exports = {select, selectSuites};

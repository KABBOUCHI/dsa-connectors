import * as core from '@actions/core'
import * as github from '@actions/github'
import { Octokit } from '@octokit/rest';
import { readFileSync } from "fs";
import glob from "glob"
//@ts-ignore
import markdownTable from 'markdown-table'

interface FileInfo {
  path: string;
  content: string;
}

const filesToIgnore = [
  'contracts/polygon/connectors/wmatic/helpers.sol',
  'contracts/fantom/connectors/wftm/helpers.sol',
]

const errors: Record<string, string[]> = {}

const checks = [
  {
    name: "Events",
    async check(files: FileInfo[]) {
      for (const file of files) {

        if (file.path.endsWith('/events.sol')) {
          continue;
        }

        if (file.path.endsWith('/interface.sol')) {
          continue;
        }

        const eventsRegex = /^\s*event\s+/gm;

        if (eventsRegex.test(file.content)) {

          if (errors[file.path] === undefined) {
            errors[file.path] = [];
          }

          errors[file.path].push("Connector events should be in a separate contract: events.sol");
        }

      }
    }
  },
  {
    name: "Interfaces",
    async check(files: FileInfo[]) {
      for (const file of files) {

        if (file.path.endsWith('/interfaces.sol')) {
          continue;
        }

        if (file.path.endsWith('/interface.sol')) {
          continue;
        }

        const eventsRegex = /^\s*interface\s+/gm;

        if (eventsRegex.test(file.content)) {

          if (errors[file.path] === undefined) {
            errors[file.path] = [];
          }

          errors[file.path].push("Interfaces should be defined in a seperate file: interface.sol");
        }

      }
    }
  },
  {
    name: "Helpers",
    async check(files: FileInfo[]) {
      for (const file of files) {

        if (!file.path.endsWith('/helpers.sol')) {
          continue;
        }

        const eventsRegex = /contract (.+) is (.+ )?Basic(.+){/gm;
        const basicContracts = Array.from(file.content.matchAll(eventsRegex));
        const contractNames = basicContracts.map(match => match[1]);
        if (!basicContracts.length) {

          if (errors[file.path] === undefined) {
            errors[file.path] = [];
          }

          errors[file.path].push("Helpers contract should inherit Basic contract from common directory");
        } else {
          const regex1 = new RegExp(`contract (?!(${contractNames.map(n => `(${n})`).join('|')})).+{`, 'gm')
          const regex2 = new RegExp(`contract (.+) is (.+ )?${contractNames.map(n => `(${n})`).join('|')}.+{`, 'gm')
          const otherContracts = Array.from(file.content.matchAll(regex1));
          const contractLines = otherContracts.map(match => match[0]);


          for (const contractLine of contractLines) {
            if (!regex2.test(contractLine)) {
              if (errors[file.path] === undefined) {
                errors[file.path] = [];
              }

              errors[file.path].push("Helpers contract should inherit Basic contract from common directory");
              break;
            }

          }
        }
      }
    }
  }

]

async function run(): Promise<void> {
  try {
    const githubToken: string = core.getInput('token')
    core.info(`Github token: 1234`)
    const octokit = new Octokit({ auth: `token ${githubToken}` });
    const context = github.context;
    const owner = context.repo.owner;
    const repo = context.repo.repo;

    const fileNames = glob.sync("contracts/**/connectors/**/*.sol");
    const files: FileInfo[] = fileNames
      .filter(fileName => !filesToIgnore.includes(fileName))
      .map(fileName => ({
        path: fileName,
        content: readFileSync(fileName, { encoding: "utf8" })
      }));

    for (const check of checks) {
      try {
        await check.check(files);
      } catch (error) {
      }
    }


    if (Object.keys(errors).length > 0) {
      const message = markdownTable(
        [
          ['File', 'Error'],
          ...Object.keys(errors).map(filePath => ([filePath, errors[filePath].join(', ')]))
        ]
      );
      await octokit.reactions.createForIssueComment({
        owner,
        repo,
        comment_id: context.payload!.pull_request!.number,
        content: message,
      });
      core.setFailed("Lint failed")
    }else{
      core.setOutput('message', 'Lint passed')
    }

  } catch (error) {
    if (error instanceof Error) core.setFailed("here " + error.message)
  }
}

run()

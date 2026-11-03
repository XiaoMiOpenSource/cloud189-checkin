require("dotenv").config();
const {
  CloudClient,
  FileTokenStore,
  logger: sdkLogger,
} = require("cloud189-sdk");
const recording = require("log4js/lib/appenders/recording");
const accounts = require("../accounts");
const { mask, delay } = require("./utils");
const push = require("./push");
const { log4js, cleanLogs, catLogs } = require("./logger");
const tokenDir = ".token";

sdkLogger.configure({
  isDebugEnabled: process.env.CLOUD189_VERBOSE === "1",
});

// 个人任务签到
const doUserTask = async (cloudClient, logger) => {
  const result = await cloudClient.userSign();
  if (result && result.isSign) {
    logger.info("个人签到任务: 今日已签到（重复执行不增加容量）");
    return;
  }
  logger.info(`个人签到任务: 获得 ${result.netdiskBonus}M 空间`);
};

// 返回 true 表示该账号本次执行成功
const run = async (userName, password, ssonCookie, userSizeInfoMap, logger) => {
  if (!userName || (!password && !ssonCookie)) {
    return false;
  }
  const before = Date.now();
  let ok = true;
  try {
    logger.log(ssonCookie ? "开始执行（SSON Cookie 登录）" : "开始执行（账号密码登录）");
    const cloudClient = new CloudClient({
      username: userName,
      password,
      ssonCookie,
      token: new FileTokenStore(`${tokenDir}/${userName}.json`),
    });
    const beforeUserSizeInfo = await cloudClient.getUserSizeInfo();
    userSizeInfoMap.set(userName, {
      cloudClient,
      userSizeInfo: beforeUserSizeInfo,
      logger,
    });
    await Promise.all([doUserTask(cloudClient, logger)]);
  } catch (e) {
    ok = false;
    if (e && e.response) {
      logger.error(`请求失败: ${e.response.statusCode}, ${e.response.body}`);
    } else {
      logger.error(e && e.message ? e.message : e);
    }
    if (e && (e.code === "ECONNRESET" || e.code === "ETIMEDOUT")) {
      logger.error("请求超时");
    }
  } finally {
    logger.log(`执行完毕, 耗时 ${((Date.now() - before) / 1000).toFixed(2)} 秒`);
  }
  return ok;
};

// 开始执行程序
async function main() {
  //  用于统计实际容量变化
  const userSizeInfoMap = new Map();
  let failed = 0;

  for (let index = 0; index < accounts.length; index += 1) {
    const account = accounts[index];
    const { userName, password, ssonCookie } = account;
    const userNameInfo = mask(userName, 0, 4);
    const logger = log4js.getLogger(userName);
    logger.addContext("user", userNameInfo);
    // eslint-disable-next-line no-await-in-loop
    const ok = await run(userName, password, ssonCookie, userSizeInfoMap, logger);
    if (!ok) failed += 1;
  }

  // 数据汇总
  for (const [
    userName,
    { cloudClient, userSizeInfo, logger },
  ] of userSizeInfoMap) {
    try {
      // eslint-disable-next-line no-await-in-loop
      const afterUserSizeInfo = await cloudClient.getUserSizeInfo();
      logger.log(
        `个人容量：⬆️  ${(
          (afterUserSizeInfo.cloudCapacityInfo.totalSize -
            userSizeInfo.cloudCapacityInfo.totalSize) /
          1024 /
          1024
        ).toFixed(2)}M/${(
          afterUserSizeInfo.cloudCapacityInfo.totalSize /
          1024 /
          1024 /
          1024
        ).toFixed(2)}G`,
        `家庭容量：⬆️  ${(
          (afterUserSizeInfo.familyCapacityInfo.totalSize -
            userSizeInfo.familyCapacityInfo.totalSize) /
          1024 /
          1024
        ).toFixed(2)}M/${(
          afterUserSizeInfo.familyCapacityInfo.totalSize /
          1024 /
          1024 /
          1024
        ).toFixed(2)}G`
      );
    } catch (e) {
      logger.error(`容量汇总失败: ${e && e.message ? e.message : e}`);
    }
  }

  return { total: accounts.length, failed };
}

(async () => {
  let summary = { total: accounts.length, failed: accounts.length };
  try {
    summary = await main();
    // 等待日志文件写入
    await delay(1000);
  } catch (e) {
    console.error(e);
  } finally {
    const logs = catLogs();
    const events = recording.replay();
    const content = events.map((e) => `${e.data.join("")}`).join("  \n");
    // 必须 await：否则进程退出时未完成的推送请求会被切断
    try {
      await push("天翼云盘自动签到任务", logs + content);
      await delay(500);
    } catch (e) {
      console.error("推送失败:", e && e.message ? e.message : e);
    }
    recording.erase();
    cleanLogs();
    // 有账号失败时返回非 0，便于计划任务 / 外部监控发现异常
    process.exitCode = summary.failed > 0 ? 1 : 0;
  }
})();

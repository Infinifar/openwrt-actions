'use strict';
'require rpc';
'require uci';
'require ui';

const setup = rpc.declare({ object: 'tailscale', method: 'setup_firewall' });
const status = rpc.declare({ object: 'tailscale', method: 'get_apply_status' });
const pause = () => new Promise(resolve => window.setTimeout(resolve, 1000));

async function waitForApply() {
    const deadline = Date.now() + 180000;
    while (Date.now() < deadline) {
        await pause();
        let result;
        try { result = await status(); }
        catch (err) { continue; } // Network reload may briefly break the reverse proxy.
        if (result.status === 'success') return;
        if (['queued', 'running'].includes(result.status)) continue;
        throw new Error('Tailscale 后台应用失败：' + (result.status || 'unknown') + '。请检查系统日志。');
    }
    throw new Error('未能确认 Tailscale 后台应用结果，请恢复连接后检查日志；不要连续重复点击。');
}

return {
    async configureFirewall(map) {
        try {
            // A form Button does not save edited advertisements automatically.
            await map.save();
            const pending = await uci.changes();
            if (Object.keys(pending || {}).length)
                throw new Error('有尚未应用的设置。请先点击“保存并应用”，等待页面刷新后再配置防火墙。');
            const result = await setup();
            if (!result || !result.success || result.error)
                throw new Error(result?.error || '防火墙配置请求失败');
            if (!result.queued)
                throw new Error('后台与页面版本不一致，请清理 LuCI 缓存后重试。');
            ui.addNotification(null, E('p', {}, '已提交后台应用，网络可能短暂重连；正在确认结果。'), 'info');
            await waitForApply();
            ui.addNotification(null, E('p', {}, '防火墙重载及 Tailscale 设置应用已完成。路由仍需在控制台批准。'), 'info');
        } catch (err) {
            ui.addNotification(null, E('p', {}, '配置防火墙失败：' + (err?.message || err)), 'error');
        }
    }
};

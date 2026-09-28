<?php

/**
 * @name crash-on-enable
 * @version 1.0.0
 * @api 5.0.0
 * @main CrashOnEnable
 * @author Riftal Games
 */

class CrashOnEnableThread extends \pocketmine\thread\Thread {
	protected function onRun() : void {
		while(true){
			sleep(1);
		}
	}
}

class CrashOnEnable extends \pocketmine\plugin\PluginBase {
	private static ?CrashOnEnableThread $thread = null;

	public function onEnable() : void {
		// A plugin thread that never ends, such as a database connector's, is
		// what makes a crashed server hang: exit() joins every live thread, so
		// only the SIGKILL the crash path sends itself can end the process.
		self::$thread = new CrashOnEnableThread();
		self::$thread->start();
		throw new \RuntimeException("crash-on-enable fixture: deliberate crash during onEnable");
	}
}

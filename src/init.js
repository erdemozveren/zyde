window.zyde = {
  invoke: async function invoke(name, ...args) {
    if (typeof name !== 'string') {
      return Promise.reject(new Error("You must specify a command name"))
    }
    if (args.length === 0) {
      return window.__zyde_raw_invoke(name, null);
    } else {
      return window.__zyde_raw_invoke(name, JSON.stringify(args));
    }
  },
};

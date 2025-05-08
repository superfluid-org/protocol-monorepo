import {
  getDefaultWallets
} from '@rainbow-me/rainbowkit';
import {
  configureChains,
  createClient
} from 'wagmi';
import {
  polygon,
  avalancheFuji
} from 'wagmi/chains'
import { publicProvider } from 'wagmi/providers/public';

export const { chains, provider } = configureChains(
  [polygon, avalancheFuji],
  [
    publicProvider()
  ]
);

export const { connectors } = getDefaultWallets({
  appName: 'SDK-redux example',
  projectId: "",
  chains
});

export const wagmiClient = createClient({
  autoConnect: false,
  connectors,
  provider
})

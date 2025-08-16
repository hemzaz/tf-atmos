import { PropsWithChildren } from 'react';
import { makeStyles } from '@material-ui/core';
import HomeIcon from '@material-ui/icons/Home';
import ExtensionIcon from '@material-ui/icons/Extension';
import LibraryBooks from '@material-ui/icons/LibraryBooks';
import CreateComponentIcon from '@material-ui/icons/AddCircleOutline';
import CloudIcon from '@material-ui/icons/Cloud';
import AttachMoneyIcon from '@material-ui/icons/AttachMoney';
import SecurityIcon from '@material-ui/icons/Security';
import LogoFull from './LogoFull';
import LogoIcon from './LogoIcon';
import {
  Settings as SidebarSettings,
  UserSettingsSignInAvatar,
} from '@backstage/plugin-user-settings';
import { SidebarSearchModal } from '@backstage/plugin-search';
import {
  Sidebar,
  sidebarConfig,
  SidebarDivider,
  SidebarGroup,
  SidebarItem,
  SidebarPage,
  SidebarScrollWrapper,
  SidebarSpace,
  useSidebarOpenState,
  Link,
} from '@backstage/core-components';
import MenuIcon from '@material-ui/icons/Menu';
import SearchIcon from '@material-ui/icons/Search';
import { MyGroupsSidebarItem } from '@backstage/plugin-org';
import GroupIcon from '@material-ui/icons/People';

const useSidebarLogoStyles = makeStyles({
  root: {
    width: sidebarConfig.drawerWidthClosed,
    height: 3 * sidebarConfig.logoHeight,
    display: 'flex',
    flexFlow: 'row nowrap',
    alignItems: 'center',
    marginBottom: -14,
  },
  link: {
    width: sidebarConfig.drawerWidthClosed,
    marginLeft: 24,
  },
});

const SidebarLogo = () => {
  const classes = useSidebarLogoStyles();
  const { isOpen } = useSidebarOpenState();

  return (
    <div className={classes.root}>
      <Link 
        to="/" 
        underline="none" 
        className={classes.link} 
        aria-label="Platform Developer Portal - Home"
        role="banner"
      >
        {isOpen ? <LogoFull /> : <LogoIcon />}
      </Link>
    </div>
  );
};

export const Root = ({ children }: PropsWithChildren<{}>) => (
  <SidebarPage>
    <Sidebar>
      <SidebarLogo />
      <SidebarGroup 
        label="Search" 
        icon={<SearchIcon />} 
        to="/search"
        role="search"
        aria-label="Global search functionality"
      >
        <SidebarSearchModal />
      </SidebarGroup>
      <SidebarDivider />
      <SidebarGroup 
        label="Platform Services" 
        icon={<MenuIcon />}
        role="navigation"
        aria-label="Main navigation menu"
      >
        {/* Global nav, not org-specific */}
        <SidebarItem 
          icon={HomeIcon} 
          to="catalog" 
          text="Service Catalog"
          aria-label="Browse and manage service catalog"
        />
        <MyGroupsSidebarItem
          singularTitle="My Team"
          pluralTitle="My Teams"
          icon={GroupIcon}
        />
        <SidebarItem 
          icon={ExtensionIcon} 
          to="api-docs" 
          text="API Documentation"
          aria-label="Browse API documentation"
        />
        <SidebarItem 
          icon={LibraryBooks} 
          to="docs" 
          text="Technical Docs"
          aria-label="Access technical documentation"
        />
        <SidebarItem 
          icon={CreateComponentIcon} 
          to="create" 
          text="Create Service"
          aria-label="Create new services and resources"
        />
        {/* End global nav */}
        <SidebarDivider />
        <SidebarScrollWrapper>
          {/* Platform-specific navigation items */}
          <SidebarItem 
            icon={CloudIcon} 
            to="atmos" 
            text="Infrastructure"
            aria-label="Manage infrastructure with Atmos"
          />
          <SidebarItem 
            icon={AttachMoneyIcon} 
            to="cost-tracking" 
            text="Cost Analysis"
            aria-label="Monitor and analyze infrastructure costs"
          />
          <SidebarItem 
            icon={SecurityIcon} 
            to="compliance" 
            text="Compliance"
            aria-label="Security and compliance dashboard"
          />
        </SidebarScrollWrapper>
      </SidebarGroup>
      <SidebarSpace />
      <SidebarDivider />
      <SidebarGroup
        label="User Settings"
        icon={<UserSettingsSignInAvatar />}
        to="/settings"
        role="complementary"
        aria-label="User account and application settings"
      >
        <SidebarSettings />
      </SidebarGroup>
    </Sidebar>
    <main role="main" aria-label="Main content area">
      {children}
    </main>
  </SidebarPage>
);

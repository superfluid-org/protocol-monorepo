import {ApiModules} from '@reduxjs/toolkit/query';

export type ModuleName = keyof ApiModules<any, any, any, any>;
